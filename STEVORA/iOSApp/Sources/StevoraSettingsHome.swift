import SwiftUI

struct StevoraSettingsHome: View {
    @EnvironmentObject private var model: StevoraModel
    @State private var routineID: String?
    @State private var confirmLogout = false

    @State private var ruleName = ""
    @State private var source: String?
    @State private var target: String?
    @State private var whenOn = true
    @State private var turnOn = true
    @State private var saving = false
    @State private var result = ""

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
                        if model.canManageHome {
                            DisclosureGroup(model.localized("Нова автоматизация", "New automation")) {
                                TextField(model.localized("Име", "Name"), text: $ruleName)
                                let devices = model.projectedEntities.filter { !$0.id.lowercased().contains("backlight") }
                                StevoraSettingsPicker(title: model.localized("Когато устройството", "When this device"),
                                    choices: devices.filter { ["light","switch","fan","binary_sensor","input_boolean"].contains($0.domain) }
                                        .map { .init(id: $0.id, name: model.displayName($0), detail: "") }, selection: $source)
                                Picker(model.localized("Премине в състояние", "Changes to"), selection: $whenOn) {
                                    Text(model.stateLabel("on")).tag(true)
                                    Text(model.stateLabel("off")).tag(false)
                                }
                                StevoraSettingsPicker(title: model.localized("Управлявай устройство", "Control device"),
                                    choices: devices.filter { model.allows($0, "toggle") }
                                        .map { .init(id: $0.id, name: model.displayName($0), detail: "") }, selection: $target)
                                Picker(model.localized("Действие", "Action"), selection: $turnOn) {
                                    Text(model.localized("Включи", "Turn on")).tag(true)
                                    Text(model.localized("Изключи", "Turn off")).tag(false)
                                }
                                Button(model.localized("Запази", "Save")) {
                                    saving = true
                                    Task {
                                        defer { saving = false }
                                        do {
                                            try await model.createRoutine(name: ruleName, source: source, whenOn: whenOn, target: target, turnOn: turnOn)
                                            ruleName = ""; source = nil; target = nil
                                            result = model.localized("Автоматизацията е записана", "Automation saved")
                                        } catch { result = model.localized("Записът е неуспешен. Провери връзката и правата.", "Could not save. Check connection and permissions.") }
                                    }
                                }.disabled(saving || ruleName.isEmpty || source == nil || target == nil)
                                if !result.isEmpty { Text(result) }
                            }
                        }
                        let available = model.projectedEntities.filter {
                            ["scene", "script", "automation"].contains($0.domain) && !$0.id.lowercased().contains("backlight")
                        }
                        if available.isEmpty {
                            Text(model.localized("Няма достъпни сцени или автоматизации", "No scenes or automations available"))
                        } else {
                            StevoraSettingsPicker(title: model.localized("Сцена или автоматизация", "Scene or automation"),
                                choices: available.map { .init(id: $0.id, name: model.displayName($0), detail: "") },
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
