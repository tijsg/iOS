import HAKit
import PromiseKit
import UserNotifications

public protocol LocalPushManagerDelegate: AnyObject {
    func localPushManager(
        _ manager: LocalPushManager,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    )
}

public class LocalPushManager {
    public let server: Server
    public weak var delegate: LocalPushManagerDelegate?

    public static let stateDidChange: Notification.Name = .init(rawValue: "LocalPushManagerStateDidChange")

    public enum State: Equatable, Codable {
        case establishing
        case unavailable
        case available(received: Int)

        mutating func increment(by count: Int = 1) {
            switch self {
            case .establishing, .unavailable:
                self = .available(received: count)
            case let .available(received: originalCount):
                self = .available(received: originalCount + count)
            }
        }

        private enum PrimitiveState: String, Codable {
            case establishing
            case unavailable
            case available
        }

        private var primitiveState: PrimitiveState {
            switch self {
            case .establishing: return .establishing
            case .unavailable: return .unavailable
            case .available: return .available
            }
        }

        private var primitiveCount: Int? {
            switch self {
            case let .available(received: count): return count
            case .unavailable, .establishing: return nil
            }
        }

        private enum CodingKeys: CodingKey {
            case primitive
            case count
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(primitiveState, forKey: .primitive)
            try container.encode(primitiveCount, forKey: .count)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let primitiveState = try container.decode(PrimitiveState.self, forKey: .primitive)
            let primitiveCount = try container.decode(Int?.self, forKey: .count)

            switch primitiveState {
            case .establishing: self = .establishing
            case .unavailable: self = .unavailable
            case .available: self = .available(received: primitiveCount ?? 0)
            }
        }
    }

    public var state: State = .establishing {
        didSet {
            NotificationCenter.default.post(name: Self.stateDidChange, object: self)
        }
    }

    private var tokens = [HACancellable]()

    public init(server: Server) {
        self.server = server

        updateSubscription()
        tokens.append(server.observe { [weak self] _ in
            self?.updateSubscription()
        })
    }

    deinit {
        invalidate()
        tokens.forEach { $0.cancel() }
    }

    public func invalidate() {
        if let subscription {
            Current.Log.info("cancelling")
            subscription.cancel()
        } else {
            Current.Log.info("no active subscription")
        }
        NotificationCenter.default.removeObserver(self)
    }

    var add: (UNNotificationRequest) -> Promise<Void> = { request in
        Promise<Void> { seal in
            UNUserNotificationCenter.current().add(request, withCompletionHandler: seal.resolve)
        }
    }

    struct SubscriptionInstance {
        let token: HACancellable
        let webhookID: String

        func cancel() {
            Current.Log.info("cancelling subscription")
            token.cancel()
        }
    }

    private var subscription: SubscriptionInstance?

    private func updateSubscription() {
        let webhookID = server.info.connection.webhookID

        guard webhookID != subscription?.webhookID else {
            // webhookID hasn't changed, so we don't need to reset
            return
        }
        subscription?.cancel()

        guard let connection = Current.api(for: server)?.connection else {
            Current.Log.error("No API available to update subscription")
            return
        }

        subscription = .init(
            token: connection.subscribe(
                to: .localPush(webhookID: webhookID, serverVersion: server.info.version),
                initiated: { [weak self] result in
                    self?.handle(initiated: result.map { _ in () })
                }, handler: { [weak self] _, value in
                    self?.handle(event: value)
                }
            ),
            webhookID: webhookID
        )
    }

    private func handle(initiated result: Swift.Result<Void, HAError>) {
        switch result {
        case let .failure(error):
            Current.Log.error("failed to subscribe to notifications: \(error)")
            state = .unavailable
        case .success:
            Current.Log.info("started")
            state = .available(received: 0)
        }
    }

    private func handle(event: LocalPushEvent) {
        Current.Log.debug("handling \(event)")

        state.increment()

        let baseContent = event.content(server: server)

        delegate?.localPushManager(self, didReceiveRemoteNotification: baseContent.userInfo)

        guard let api = Current.api(for: server) else {
            Current.Log.error("No API available to handle local push event")
            return
        }

        firstly {
            Current.notificationAttachmentManager.content(from: baseContent, api: api)
        }.recover { error in
            Current.Log.error("failed to get content, giving default: \(error)")
            return .value(baseContent)
        }.then { [add] content -> Promise<Void> in
            add(UNNotificationRequest(identifier: event.identifier, content: content, trigger: nil))
        }.then { [subscription] () -> Promise<Void> in
            if let confirmID = event.confirmID, let webhookID = subscription?.webhookID {
                return api.connection.send(.localPushConfirm(
                    webhookID: webhookID,
                    confirmID: confirmID
                )).promise.map { _ in () }
            } else {
                return .value(())
            }
        }.done {
            Current.Log.info("added local notification")
        }.catch { error in
            Current.Log.error("failed to add local notification: \(error)")
        }
    }
}
