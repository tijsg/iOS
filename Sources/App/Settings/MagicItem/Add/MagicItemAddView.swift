import Shared
import SwiftUI

struct MagicItemAddView: View {
    enum Context {
        case watch
        case carPlay
        case widget
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = MagicItemAddViewModel()

    let context: Context
    let itemToAdd: (MagicItem?) -> Void

    var body: some View {
        NavigationView {
            VStack {
                Picker(L10n.MagicItem.ItemType.Selection.List.title, selection: $viewModel.selectedItemType) {
                    if [.carPlay, .widget].contains(context) {
                        Text(L10n.MagicItem.ItemType.Entity.List.title)
                            .tag(MagicItemAddType.entities)
                    }
                    if context != .widget {
                        Text(L10n.MagicItem.ItemType.Script.List.title)
                            .tag(MagicItemAddType.scripts)
                        Text(L10n.MagicItem.ItemType.Scene.List.title)
                            .tag(MagicItemAddType.scenes)
                        Text(L10n.MagicItem.ItemType.Action.List.title)
                            .tag(MagicItemAddType.actions)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                List {
                    switch viewModel.selectedItemType {
                    case .actions:
                        actionsList
                    case .scripts:
                        scriptsPerServerList
                    case .scenes:
                        scenesPerServerList
                    case .entities:
                        entitiesPerServerList
                    }
                }
                .searchable(text: $viewModel.searchText)
            }
            .onAppear {
                autoSelectItemType()
                viewModel.loadContent()
            }
            .toolbar(content: {
                Button(action: {
                    dismiss()
                }, label: {
                    Image(systemName: "xmark.circle.fill")
                })
                .tint(.white)
            })
        }
        .preferredColorScheme(.dark)
    }

    private func autoSelectItemType() {
        switch context {
        case .watch:
            viewModel.selectedItemType = .scripts
        case .carPlay, .widget:
            viewModel.selectedItemType = .entities
        }
    }

    @ViewBuilder
    private var actionsList: some View {
        actionsDeprecationDisclaimer
        ForEach(viewModel.actions, id: \.ID) { action in
            if visibleForSearch(title: action.Text) {
                Button(action: {
                    itemToAdd(.init(id: action.ID, serverId: action.serverIdentifier, type: .action))
                    dismiss()
                }, label: {
                    makeItemRow(title: action.Text, imageSystemName: "plus.circle.fill")
                })
                .tint(.white)
            }
        }
    }

    private var actionsDeprecationDisclaimer: some View {
        Section {
            Button {
                viewModel.selectedItemType = .scripts
            } label: {
                Text(L10n.MagicItem.ItemType.Action.List.Warning.title)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var scriptsPerServerList: some View {
        ForEach(Array(viewModel.scripts.keys), id: \.identifier) { server in
            Section(server.info.name) {
                list(entities: viewModel.scripts[server] ?? [], serverId: server.identifier.rawValue, type: .script)
            }
        }
    }

    @ViewBuilder
    private var scenesPerServerList: some View {
        ForEach(Array(viewModel.scenes.keys), id: \.identifier) { server in
            Section(server.info.name) {
                list(entities: viewModel.scenes[server] ?? [], serverId: server.identifier.rawValue, type: .scene)
            }
        }
    }

    @ViewBuilder
    private var entitiesPerServerList: some View {
        ForEach(Array(viewModel.entities.keys), id: \.identifier) { server in
            Section(server.info.name) {
                list(entities: viewModel.entities[server] ?? [], serverId: server.identifier.rawValue, type: .entity)
            }
        }
    }

    @ViewBuilder
    private func list(entities: [HAAppEntity], serverId: String, type: MagicItem.ItemType) -> some View {
        ForEach(entities, id: \.id) { entity in
            if visibleForSearch(title: entity.name) || visibleForSearch(title: entity.entityId) {
                NavigationLink {
                    MagicItemCustomizationView(
                        mode: .add,
                        displayAction: context == .widget,
                        item: .init(
                            id: entity.entityId,
                            serverId: serverId,
                            type: type
                        )
                    ) { itemToAdd in
                        self.itemToAdd(itemToAdd)
                        dismiss()
                    }
                } label: {
                    makeItemRow(title: entity.name, subtitle: entity.entityId, entityIcon: entity.icon)
                }
            }
        }
    }

    private func makeItemRow(
        title: String,
        subtitle: String? = nil,
        imageSystemName: String? = nil,
        entityIcon: String? = nil,
        imageColor: Color? = .green
    ) -> some View {
        HStack(spacing: Spaces.one) {
            HStack {
                if let entityIcon {
                    Image(uiImage: MaterialDesignIcons(serversideValueNamed: entityIcon, fallback: .gridIcon).image(ofSize: .init(width: 24, height: 24), color: .white))
                }
            }
            .frame(width: 24, height: 24)
            VStack {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let subtitle {
                    Text(subtitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
            if let imageSystemName, let imageColor {
                Image(systemName: imageSystemName)
                    .foregroundStyle(.white, imageColor)
                    .font(.title3)
            }
        }
    }

    private func visibleForSearch(title: String) -> Bool {
        viewModel.searchText.count < 3 || title.lowercased().contains(viewModel.searchText.lowercased())
    }
}

#Preview {
    MagicItemAddView(context: .carPlay) { _ in
    }
}
