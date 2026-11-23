import SwiftUI

struct StevoraSettingsHome: View {
    @EnvironmentObject private var model: StevoraModel
    @State private var routineID: String?
    @State private var confirmLogout = false

    private var account: String { model.localized("Профил и език", "Account and language") }
    private var privacy: String { model.localized("Местоположение", "Location sharing") }
    private var connection: String { model.localized("Връзка с дома", "Home connection") }
    private var routines: String { model.localized("Сцени и автоматизации", "Scenes and automations") }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    Form {
                        if let name = model.accountName {
                            LabeledContent(model.localized("Профил", "Account"), value: name)
                            LabeledContent(model.localized("Роля", "Role"), value: model.isAdmin
                                ? model.localized("Администратор", "Administrator") : model.localized("Потребител", "User"))
                        }
                        Picker(model.localized("Език", "Language"), selection: Binding(
                            get: { model.language }, set: { value in Task { await model.setLanguage(value) } }
                        )) {
                            Text("Български").tag("bg")
                            Text("English").tag("en")
                        }.disabled(model.savingLanguage || !model.liveConnected)
                        Button(role: .destructive) { confirmLogout = true } label: {
                            Label(model.localized("Изход от профила", "Sign out"), systemImage: "rectangle.portrait.and.arrow.right")
                        }.confirmationDialog(model.localized("Изход от STEVORA?", "Sign out of STEVORA?"), isPresented: $confirmLogout) {
                            Button(model.localized("Изход", "Sign out"), role: .destructive) { model.logout() }
                            Button(model.localized("Отказ", "Cancel"), role: .cancel) {}
                        }
                        if let error = model.error { Text(error).foregroundStyle(.orange) }
                    }.navigationTitle(account)
                } label: { Label(account, systemImage: "person.crop.circle") }
                NavigationLink {
                    ScrollView { StevoraPresenceSettings(presence: model.presence).padding() }
                        .navigationTitle(privacy)
                } label: { Label(privacy, systemImage: "location.circle") }
                .accessibilityIdentifier("settings.location")
                NavigationLink {
                    Form {
                        LabeledContent(model.localized("Състояние", "Status"), value: model.connectionMode)
                        Text(model.address).textSelection(.enabled)
                        if let manifest = model.stevoraManifest {
                            LabeledContent(model.localized("Ревизия на дома", "Home revision"), value: String(manifest.revision))
                            if let url = URL(string: model.address) {
                                Link(model.localized("Отвори STEVORA OS", "Open STEVORA OS"), destination: url)
                            }
                        }
                        Button(model.localized("Обнови", "Refresh")) { Task { await model.refresh() } }
                    }.navigationTitle(connection)
                } label: { Label(connection, systemImage: "house") }
                NavigationLink {
                    Form {
                        let available = model.projectedEntities.filter {
                            ["scene", "script", "automation"].contains($0.domain) && !$0.id.lowercased().contains("backlight")
                        }
                        if available.isEmpty {
                            Text(model.localized("Няма достъпни сцени или автоматизации", "No scenes or automations available"))
                        } else {
                            let names = Dictionary((model.stevoraManifest?.entities ?? []).map { ($0.entityId, $0.name) },
                                                   uniquingKeysWith: { first, _ in first })
                            StevoraSettingsPicker(title: model.localized("Сцена или автоматизация", "Scene or automation"),
                                choices: available.map { .init(id: $0.id, name: names[$0.id] ?? $0.name, detail: $0.id) },
                                selection: $routineID)
                            if let entity = available.first(where: { $0.id == routineID }) {
                                Button { Task { await model.runRoutine(entity) } } label: {
                                    Label(model.localized("Стартирай", "Run"), systemImage: "play.circle")
                                }.disabled(!model.liveConnected || model.stevoraManifest?.controllable?.contains(entity.id) != true ||
                                    ["unavailable", "unknown"].contains(entity.state))
                            }
                        }
                    }.navigationTitle(routines)
                } label: { Label(routines, systemImage: "play.square.stack") }
                .accessibilityIdentifier("settings.routines")
            } header: { Text(model.accountName ?? model.localized("Лични настройки", "Personal settings")) }
            if model.canManageHome {
                Section(model.localized("Управление на дома", "Manage home")) {
                    ForEach(StevoraManagersView.Page.allCases, id: \.self) { page in
                        NavigationLink {
                            StevoraManagersView(model: model, page: page)
                        } label: { Label(page.title(model), systemImage: page.icon) }
                        .accessibilityIdentifier("settings.manager.\(page)")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background)
        .navigationTitle(model.localized("Настройки", "Settings"))
        .refreshable { await model.refresh() }
    }
}

#Preview {
    NavigationStack { StevoraSettingsHome().environmentObject(StevoraModel()) }.preferredColorScheme(.dark)
}
