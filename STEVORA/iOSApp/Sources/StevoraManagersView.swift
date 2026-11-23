import SwiftUI

/// Live, server-authorized manager. No local admin flag grants access.
struct StevoraManagersView: View {
    @ObservedObject var model: StevoraModel
    enum Page: CaseIterable {
        case rooms, devices, assistants

        @MainActor func title(_ model: StevoraModel) -> String {
            switch self {
            case .rooms: return model.localized("Стаи", "Rooms")
            case .devices: return model.localized("Устройства", "Devices")
            case .assistants: return model.localized("Асистенти", "Assistants")
            }
        }

        var icon: String {
            switch self {
            case .rooms: return "square.grid.2x2"
            case .devices: return "switch.2"
            case .assistants: return "waveform"
            }
        }
    }

    let page: Page
    @State private var roster: [StevoraAdminAPI.AssistantUser]?
    @State private var selectedRoom: String?
    @State private var selectedEntity: String?
    @State private var selectedUser: String?
    @State private var saving = false
    @State private var rooms: StevoraAdminAPI.RoomSnapshot?
    @State private var assistants: StevoraAdminAPI.AssistantSnapshot?
    @State private var selectedDefault = ""
    @State private var userPipelines: [String: String] = [:]
    @State private var roomAliases: [String: String] = [:]
    @State private var entityAliases: [String: String] = [:]
    @State private var roomOrder: [String] = []
    @State private var bilingualRooms: [String: [String: String]] = [:]
    @State private var bilingualEntities: [String: [String: String]] = [:]
    @State private var deviceProfiles: [String: StevoraAdminAPI.DeviceProfile] = [:]
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private func gateway() -> StevoraAssistantGateway {
        StevoraAssistantGateway(address: model.address, token: model.token, allowLocalHTTP: model.allowLocalHTTP)
    }

    private func load() async {
        guard model.canManageHome, !model.token.isEmpty else {
            rooms = nil
            assistants = nil
            return
        }
        loading = true
        defer { loading = false }
        do {
            let service = gateway()
            switch page {
            case .assistants:
                let result = try await service.adminRequest("stevora/admin/assistants/get")
                try Task.checkCancellation()
                assistants = try JSONDecoder().decode(StevoraAdminAPI.AssistantSnapshot.self,
                    from: JSONSerialization.data(withJSONObject: result))
                selectedDefault = assistants?.settings.defaultPipeline ?? ""
                userPipelines = assistants?.settings.userPipelines ?? [:]
            case .rooms, .devices:
                let result = try await service.adminRequest("stevora/admin/rooms/get")
                try Task.checkCancellation()
                rooms = try JSONDecoder().decode(StevoraAdminAPI.RoomSnapshot.self,
                    from: JSONSerialization.data(withJSONObject: result))
                roomAliases = rooms?.roomAliases ?? [:]
                entityAliases = rooms?.entityAliases ?? [:]
                let known = rooms?.rooms.map(\.id) ?? []
                let saved = (rooms?.roomOrder ?? []).filter { known.contains($0) }
                roomOrder = saved + known.filter { !saved.contains($0) }
                bilingualRooms = rooms?.translations?.rooms ?? [:]
                bilingualEntities = rooms?.translations?.entities ?? [:]
                deviceProfiles = rooms?.deviceProfiles ?? [:]
                if page == .devices {
                    roster = nil
                    if let result = try? await service.adminRequest("stevora/admin/assistants/get"),
                       let data = try? JSONSerialization.data(withJSONObject: result) {
                        roster = try? JSONDecoder().decode(StevoraAdminAPI.AssistantSnapshot.self, from: data).users
                    }
                    try Task.checkCancellation()
                }
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            rooms = nil
            assistants = nil
            errorMessage = error.localizedDescription
        }
    }

    private func setVisibility(_ entityID: String, _ visibility: String) async {
        guard model.canManageHome, !saving, let rooms else { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await gateway().adminRequest("stevora/admin/rooms/update", fields: [
                "expected_revision": rooms.revision,
                "entities": [["entity_id": entityID, "visibility": visibility]]
            ])
            await load()
            await model.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveRoomLayout(_ id: String) async {
        guard model.canManageHome, !saving, let rooms else { return }
        saving = true
        defer { saving = false }
        do {
            var fields: [String: Any] = [
                "expected_revision": rooms.revision,
                "room_aliases": rooms.roomAliases.merging(roomAliases.filter { $0.key == id }) { _, new in new },
                "entity_aliases": entityAliases,
                "room_labels": [id: ["bg": bilingualRooms[id]?["bg"] ?? "", "en": bilingualRooms[id]?["en"] ?? ""]]
            ]
            let ids = rooms.rooms.map(\.id)
            let saved = rooms.roomOrder.filter { ids.contains($0) }
            if roomOrder != saved + ids.filter({ !saved.contains($0) }) { fields["room_order"] = roomOrder }
            _ = try await gateway().adminRequest("stevora/admin/rooms/aliases/update", fields: fields)
            statusMessage = model.localized("Стаите са запазени", "Room layout saved")
            await load()
            await model.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveTranslations(entityID: String) async {
        guard model.canManageHome, !saving, let rooms else { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await gateway().adminRequest("stevora/admin/translations/update", fields: [
                "expected_revision": rooms.revision,
                "rooms": [String: Any](), "entities": [entityID: ["bg": bilingualEntities[entityID]?["bg"] ?? "", "en": bilingualEntities[entityID]?["en"] ?? ""]]
            ])
            statusMessage = model.localized("Преводите са запазени", "Translations saved")
            await load()
            await model.refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveDevice(_ entityID: String) async {
        guard model.canManageHome, !saving, let rooms, let profile = deviceProfiles[entityID] else { return }
        saving = true
        defer { saving = false }
        do {
            let encoded = try JSONEncoder().encode(profile)
            let value = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
            _ = try await gateway().adminRequest("stevora/admin/devices/update", fields: [
                "expected_revision": rooms.revision,
                "profiles": [entityID: value]
            ])
            statusMessage = model.localized("Устройството е запазено", "Device saved")
            await load()
            await model.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAssistant() async {
        guard model.canManageHome, !saving, let assistants else { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await gateway().adminRequest("stevora/admin/assistants/update", fields: [
                "expected_revision": assistants.revision,
                "default_pipeline": selectedDefault.isEmpty ? NSNull() : selectedDefault as Any,
                "user_pipelines": userPipelines
            ])
            statusMessage = model.localized("Асистентът е запазен", "Assistant saved")
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func roomName(_ room: StevoraAdminAPI.RoomSnapshot.Room) -> String {
        let translated = rooms?.translations?.rooms[room.id]?[model.language] ?? ""
        if !translated.isEmpty { return translated }
        return rooms?.roomAliases[room.id] ?? room.name
    }

    private func deviceChoices(_ snapshot: StevoraAdminAPI.RoomSnapshot) -> [StevoraSettingsPicker.Choice] {
        let areas = Dictionary(snapshot.rooms.map { ($0.id, roomName($0)) }, uniquingKeysWith: { first, _ in first })
        return snapshot.entities.map { entity in
            let names = [snapshot.translations?.entities[entity.id]?[model.language],
                         snapshot.deviceProfiles[entity.id]?.name, snapshot.entityAliases[entity.id], entity.name]
            let label = names.compactMap { $0 }.first { !$0.isEmpty } ?? entity.id
            let detail = [entity.areaID.flatMap { areas[$0] }, entity.name == label ? nil : entity.name, entity.id]
                .compactMap { $0 }.joined(separator: " · ")
            return .init(id: entity.id, name: label, detail: detail)
        }
    }

    var body: some View {
        Form {
            if model.canManageHome {
                if loading || saving { ProgressView() }
                if let errorMessage { Text(errorMessage).foregroundStyle(.orange) }
                if let statusMessage { Text(statusMessage).foregroundStyle(Brand.mint) }
                switch page {
                case .rooms:
                    if let rooms { roomEditor(rooms) }
                case .devices:
                    if let rooms { deviceEditor(rooms) }
                case .assistants:
                    if let assistants { assistantEditor(assistants) }
                }
                Button(model.localized("Обнови", "Refresh")) { Task { await load() } }
            } else {
                Text(model.localized("Нужен е администраторски достъп до свързания дом.",
                                     "Administrator access to the connected home is required."))
            }
        }
        .disabled(loading || saving)
        .scrollContentBackground(.hidden)
        .background(Brand.background)
        .navigationTitle(page.title(model))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.canManageHome) { await load() }
    }

    @ViewBuilder private func roomEditor(_ snapshot: StevoraAdminAPI.RoomSnapshot) -> some View {
        StevoraSettingsPicker(title: model.localized("Стая", "Room"),
            choices: snapshot.rooms.map { .init(id: $0.id, name: roomName($0), detail: $0.id) }, selection: $selectedRoom)
        if let room = snapshot.rooms.first(where: { $0.id == selectedRoom }) {
            Section(model.localized("Име и подредба", "Name and order")) {
                TextField(room.name, text: Binding(get: { roomAliases[room.id] ?? room.name },
                                                 set: { roomAliases[room.id] = $0 }))
                if let index = roomOrder.firstIndex(of: room.id) {
                    Stepper(value: Binding(get: { index + 1 }, set: { next in
                        guard let current = roomOrder.firstIndex(of: room.id), roomOrder.indices.contains(next - 1) else { return }
                        roomOrder.remove(at: current)
                        roomOrder.insert(room.id, at: next - 1)
                    }), in: 1...max(1, roomOrder.count)) {
                        LabeledContent(model.localized("Позиция", "Position"), value: "\(index + 1) / \(roomOrder.count)")
                    }
                }
            }
            Section("BG / EN") {
                ForEach(["bg", "en"], id: \.self) { locale in
                    TextField(locale.uppercased(), text: Binding(get: { bilingualRooms[room.id]?[locale] ?? "" },
                        set: { bilingualRooms[room.id, default: [:]][locale] = $0 }))
                }
                Button(model.localized("Запази стаята", "Save room")) { Task { await saveRoomLayout(room.id) } }
            }
        }
    }

    private var displayCategories: [StevoraSettingsPicker.Choice] {
        [
            .init(id: "auto", name: model.localized("Автоматично", "Automatic")),
            .init(id: "lighting", name: model.localized("Осветление", "Lighting")),
            .init(id: "switches", name: model.localized("Ключове", "Switches")),
            .init(id: "climate", name: model.localized("Климат", "Climate")),
            .init(id: "fans", name: model.localized("Вентилатори", "Fans")),
            .init(id: "covers", name: model.localized("Щори", "Covers")),
            .init(id: "media", name: model.localized("Медия", "Media")),
            .init(id: "sensors", name: model.localized("Датчици", "Sensors")),
            .init(id: "binary_sensors", name: model.localized("Двоични датчици", "Binary sensors")),
            .init(id: "locks", name: model.localized("Брави", "Locks"))
        ]
    }

    @ViewBuilder private func deviceEditor(_ snapshot: StevoraAdminAPI.RoomSnapshot) -> some View {
        StevoraSettingsPicker(title: model.localized("Устройство", "Device"), choices: deviceChoices(snapshot), selection: $selectedEntity)
        if let entity = snapshot.entities.first(where: { $0.id == selectedEntity }) {
            Section(model.localized("Видимост", "Visibility")) {
                if entity.disabled || entity.hidden {
                    Label(model.localized("Скрито или деактивирано в дома", "Hidden or disabled in this home"), systemImage: "lock")
                } else {
                    Picker(model.localized("Показване в дома", "Show in home"), selection: Binding(
                        get: { snapshot.visibility[entity.id] ?? "default" },
                        set: { value in Task { await setVisibility(entity.id, value) } }
                    )) {
                        Text(model.localized("Автоматично", "Automatic")).tag("default")
                        Text(model.localized("Включи", "Include")).tag("include")
                        Text(model.localized("Изключи", "Exclude")).tag("exclude")
                    }
                }
            }
            Section(model.localized("Персонализиране", "Customize")) {
                TextField(model.localized("Име", "Name"), text: Binding(
                    get: { deviceProfiles[entity.id]?.name ?? "" },
                    set: { deviceProfiles[entity.id, default: .empty].name = $0 }))
                TextField("mdi:icon", text: Binding(get: { deviceProfiles[entity.id]?.icon ?? "" },
                    set: { deviceProfiles[entity.id, default: .empty].icon = $0 }))
                Picker(model.localized("Изглед", "Layout"), selection: Binding(
                    get: { deviceProfiles[entity.id]?.layout ?? "compact" },
                    set: { deviceProfiles[entity.id, default: .empty].layout = $0 }
                )) {
                    Text(model.localized("Информация", "Information")).tag("info")
                    Text(model.localized("Компактен", "Compact")).tag("compact")
                    Text(model.localized("Разширен", "Expanded")).tag("expanded")
                }
                Picker(model.localized("Категория", "Display category"), selection: Binding(
                    get: { deviceProfiles[entity.id]?.displayCategory ?? "auto" },
                    set: { deviceProfiles[entity.id, default: .empty].displayCategory = $0 }
                )) {
                    ForEach(displayCategories, id: \.id) { category in Text(category.name).tag(category.id) }
                }
                StevoraSettingsPicker(title: model.localized("Стая", "Room"),
                    choices: [.init(id: "", name: model.localized("Автоматично", "Automatic"))] +
                        snapshot.rooms.map { .init(id: $0.id, name: roomName($0)) },
                    selection: Binding(get: { deviceProfiles[entity.id]?.areaId ?? "" },
                        set: { deviceProfiles[entity.id, default: .empty].areaId = $0?.isEmpty == false ? $0 : nil }))
                Toggle(model.localized("Автоматични контроли", "Automatic controls"), isOn: Binding(
                    get: { deviceProfiles[entity.id]?.controls == nil },
                    set: { deviceProfiles[entity.id, default: .empty].controls = $0 ? nil : [] }))
                if let controls = deviceProfiles[entity.id]?.controls {
                    let options = Set((entity.availableControls ?? []) + controls).sorted()
                    StevoraSettingsPicker(title: model.localized("Избрани контроли", "Selected controls"),
                        choices: options.map { .init(id: $0, name: $0.replacingOccurrences(of: "_", with: " ")) },
                        selection: .constant(nil), multiple: Binding(get: { Set(deviceProfiles[entity.id]?.controls ?? []) },
                            set: { deviceProfiles[entity.id, default: .empty].controls = $0.sorted() }))
                }
                let ids = deviceProfiles[entity.id]?.userIds ?? []
                if let roster {
                    let known = Set(roster.map(\.id))
                    let options = roster.map { StevoraSettingsPicker.Choice(id: $0.id, name: $0.name) }
                        + ids.filter { !known.contains($0) }.map { .init(id: $0, name: $0) }
                    StevoraSettingsPicker(title: model.localized("Видимост по потребители", "Audience"),
                        choices: options, selection: .constant(nil),
                        multiple: Binding(get: { Set(deviceProfiles[entity.id]?.userIds ?? []) },
                                          set: { deviceProfiles[entity.id, default: .empty].userIds = $0.sorted() }))
                    if ids.isEmpty {
                        Text(model.localized("Всички потребители с достъп в дома.", "All users with access in this home."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(model.localized("Списъкът с потребители е недостъпен. Обнови, за да промениш достъпа.",
                                         "User list unavailable. Refresh to change the audience.")).font(.caption)
                }
                Button(model.localized("Запази устройството", "Save device")) { Task { await saveDevice(entity.id) } }
            }
            Section("BG / EN") {
                ForEach(["bg", "en"], id: \.self) { locale in
                    TextField(locale.uppercased(), text: Binding(get: { bilingualEntities[entity.id]?[locale] ?? "" },
                        set: { bilingualEntities[entity.id, default: [:]][locale] = $0 }))
                }
                Button(model.localized("Запази преводите", "Save translations")) { Task { await saveTranslations(entityID: entity.id) } }
            }
        }
    }

    @ViewBuilder private func assistantEditor(_ snapshot: StevoraAdminAPI.AssistantSnapshot) -> some View {
        let pipelines = snapshot.pipelines.map { StevoraSettingsPicker.Choice(id: $0.id, name: $0.name) }
        StevoraSettingsPicker(title: model.localized("Основен асистент", "Default assistant"),
            choices: [.init(id: "", name: model.localized("Автоматично", "Automatic"))] + pipelines,
            selection: Binding(get: { selectedDefault }, set: { selectedDefault = $0 ?? "" }))
        StevoraSettingsPicker(title: model.localized("Потребител", "User"),
            choices: snapshot.users.map { .init(id: $0.id, name: $0.name) }, selection: $selectedUser)
        if let user = snapshot.users.first(where: { $0.id == selectedUser }) {
            StevoraSettingsPicker(title: model.localized("Личен асистент", "Personal assistant"),
                choices: [.init(id: "", name: model.localized("Наследи основния", "Use default"))] + pipelines,
                selection: Binding(get: { userPipelines[user.id] ?? "" },
                    set: { userPipelines[user.id] = $0?.isEmpty == false ? $0 : nil }))
        }
        Button(model.localized("Запази асистента", "Save assistant")) { Task { await saveAssistant() } }
    }
}

#Preview {
    let model = StevoraModel()
    NavigationStack { StevoraManagersView(model: model, page: .rooms) }.environmentObject(model)
}
