import AppIntents
import RealmSwift
import Shared
import WidgetKit

@available(iOS 17, *)
struct WidgetActionsAppIntentTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetActionsEntry
    typealias Intent = WidgetActionsAppIntent

    @MainActor
    func snapshot(for configuration: WidgetActionsAppIntent, in context: Context) async -> WidgetActionsEntry {
        Self.entry(for: configuration, in: context)
    }

    @MainActor
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        .init(
            entries: [Self.entry(for: configuration, in: context)],
            policy: .after(
                Current.date()
                    .addingTimeInterval(WidgetActionsDataSource.expiration.converted(to: .seconds).value)
            )
        )
    }

    @MainActor
    func placeholder(in context: Context) -> WidgetActionsEntry {
        let count = WidgetBasicContainerView.maximumCount(family: context.family)
        let actions = stride(from: 0, to: count, by: 1).map { _ in
            with(Action()) {
                $0.Text = "Redacted Text"
                $0.IconName = MaterialDesignIcons.bedEmptyIcon.name
            }
        }

        return WidgetActionsEntry(actions: actions)
    }

    @MainActor
    private static func entry(for configuration: Intent, in context: Context) -> Entry {
        if let existing = configuration.actions?.compactMap({ $0.asAction() }), !existing.isEmpty {
            return .init(actions: existing)
        } else {
            return .init(actions: Self.defaultActions(in: context))
        }
    }

    @MainActor
    private static func defaultActions(in context: Context) -> [Action] {
        let allActions = WidgetActionsDataSource.actions
        let maxCount = WidgetBasicContainerView.maximumCount(family: context.family)

        switch allActions.count {
        case 0: return []
        case ...maxCount: return Array(allActions)
        default: return Array(allActions[0 ..< maxCount])
        }
    }
}

@available(iOS 17, *)
extension IntentActionAppEntity {
    func asAction() -> Action? {
        guard id.isEmpty == false else {
            return nil
        }

        guard let result = Current.realm(objectTypes: [Action.self, RLMScene.self]).object(
            ofType: Action.self,
            forPrimaryKey: id
        ) else {
            return nil
        }

        return result
    }
}

enum WidgetActionsDataSource {
    static var expiration: Measurement<UnitDuration> {
        .init(value: 24, unit: .hours)
    }

    static var actions: Results<Action> {
        Current.realm(objectTypes: [Action.self, RLMScene.self]).objects(Action.self)
            .sorted(byKeyPath: #keyPath(Action.Position))
    }
}
