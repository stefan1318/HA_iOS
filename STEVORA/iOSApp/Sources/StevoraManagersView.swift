import SwiftUI

/// Live, server-authorized manager. No local admin flag grants access.
struct StevoraManagersView: View {
    @ObservedObject var model: StevoraModel
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
        guard !model.token.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            let service = gateway()
            let roomResult = try await service.adminRequest("stevora/admin/rooms/get")
            let assistantResult = try await service.adminRequest("stevora/admin/assistants/get")
            let roomData = try JSONSerialization.data(withJSONObject: roomResult)
            let assistantData = try JSONSerialization.data(withJSONObject: assistantResult)
            rooms = try JSONDecoder().decode(StevoraAdminAPI.RoomSnapshot.self, from: roomData)
            roomAliases = rooms?.roomAliases ?? [:]
            entityAliases = rooms?.entityAliases ?? [:]
            roomOrder = rooms?.roomOrder ?? []
            bilingualRooms = rooms?.translations?.rooms ?? [:]
            bilingualEntities = rooms?.translations?.entities ?? [:]
            deviceProfiles = rooms?.deviceProfiles ?? [:]
            assistants = try JSONDecoder().decode(StevoraAdminAPI.AssistantSnapshot.self, from: assistantData)
            selectedDefault = assistants?.settings.defaultPipeline ?? ""
            userPipelines = assistants?.settings.userPipelines ?? [:]
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setVisibility(_ entityID: String, _ visibility: String) async {
        guard let rooms else { return }
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

    private func saveRoomLayout() async {
        guard let rooms else { return }
        do {
            _ = try await gateway().adminRequest("stevora/admin/rooms/aliases/update", fields: [
                "expected_revision": rooms.revision,
                "room_aliases": roomAliases,
                "entity_aliases": entityAliases,
                "room_order": roomOrder
            ])
            statusMessage = model.localized("Стаите са запазени", "Room layout saved")
            await load()
            await model.refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveTranslations(roomID: String? = nil, entityID: String? = nil) async {
        guard let rooms else { return }
        do {
            let selectedRooms = roomID.map { [$0: bilingualRooms[$0] ?? [:]] } ?? [:]
            let selectedEntities = entityID.map { [$0: bilingualEntities[$0] ?? [:]] } ?? [:]
            _ = try await gateway().adminRequest("stevora/admin/translations/update", fields: [
                "expected_revision": rooms.revision,
                "rooms": selectedRooms, "entities": selectedEntities
            ])
            statusMessage = model.localized("Преводите са запазени", "Translations saved")
            await load()
            await model.refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    private func saveDevice(_ entityID: String) async {
        guard let rooms, let profile = deviceProfiles[entityID] else { return }
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
        guard let assistants else { return }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.localized("STEVORA МЕНИДЖЪРИ", "STEVORA MANAGERS"))
                .font(.headline)
            if loading { ProgressView() }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.orange)
            }
            if let statusMessage {
                Text(statusMessage).font(.footnote).foregroundStyle(.green)
            }
            if let assistants {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.localized("Assistant Manager", "Assistant Manager"))
                        .font(.headline)
                    Picker(model.localized("Основен асистент", "Default assistant"), selection: $selectedDefault) {
                        Text(model.localized("Без избор", "No selection")).tag("")
                        ForEach(assistants.pipelines, id: \.id) { pipeline in
                            Text(pipeline.name).tag(pipeline.id)
                        }
                    }
                    ForEach(assistants.users) { user in
                        Picker(user.name, selection: Binding(
                            get: { userPipelines[user.id] ?? "" },
                            set: { next in
                                if next.isEmpty { userPipelines.removeValue(forKey: user.id) }
                                else { userPipelines[user.id] = next }
                            }
                        )) {
                            Text(model.localized("Наследи основния", "Use default")).tag("")
                            ForEach(assistants.pipelines, id: \.id) { pipeline in
                                Text(pipeline.name).tag(pipeline.id)
                            }
                        }
                    }
                    Button(model.localized("Запази асистента", "Save assistant")) {
                        Task { await saveAssistant() }
                    }
                    .disabled(loading)
                }
            }
            if let rooms {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.localized("Device & Room Manager", "Device & Room Manager"))
                        .font(.headline)
                    ForEach(rooms.rooms) { room in
                        HStack {
                            TextField(room.name, text: Binding(
                                get: { roomAliases[room.id] ?? room.name },
                                set: { roomAliases[room.id] = $0 }
                            ))
                            Button("↑") {
                                if !roomOrder.contains(room.id) { roomOrder = rooms.rooms.map(\.id) }
                                if let index = roomOrder.firstIndex(of: room.id), index > 0 {
                                    roomOrder.swapAt(index, index - 1)
                                }
                            }
                        }
                    }
                    ForEach(rooms.rooms) { room in
                        DisclosureGroup(room.name + " · BG/EN") {
                            ForEach(["bg", "en"], id: \.self) { locale in
                                TextField(locale.uppercased(), text: Binding(
                                    get: { bilingualRooms[room.id]?[locale] ?? "" },
                                    set: { bilingualRooms[room.id, default: [:]][locale] = $0 }
                                ))
                            }
                            Button("Save BG/EN") { Task { await saveTranslations(roomID: room.id) } }
                        }
                    }
                    Button(model.localized("Запази стаите", "Save rooms")) {
                        Task { await saveRoomLayout() }
                    }
                    Text("\(rooms.entities.count) entities")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(rooms.entities) { entity in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading) {
                                Text(entity.name).font(.subheadline)
                                Text(entity.entityId).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entity.disabled || entity.hidden {
                                Image(systemName: "lock.fill")
                            } else {
                                Menu {
                                    Button(model.localized("Автоматично", "Automatic")) {
                                        Task { await setVisibility(entity.entityId, "default") }
                                    }
                                    Button(model.localized("Включи", "Include")) {
                                        Task { await setVisibility(entity.entityId, "include") }
                                    }
                                    Button(model.localized("Изключи", "Exclude")) {
                                        Task { await setVisibility(entity.entityId, "exclude") }
                                    }
                                } label: {
                                    Image(systemName: entity.included ? "eye" : "eye.slash")
                                }
                            }
                        }
                        DisclosureGroup("BG / EN") {
                            ForEach(["bg", "en"], id: \.self) { locale in
                                TextField(locale.uppercased(), text: Binding(
                                    get: { bilingualEntities[entity.entityId]?[locale] ?? "" },
                                    set: { bilingualEntities[entity.entityId, default: [:]][locale] = $0 }
                                ))
                            }
                            Button("Save BG/EN") { Task { await saveTranslations(entityID: entity.entityId) } }
                        }
                        DisclosureGroup(model.localized("Персонализиране", "Customize")) {
                            TextField(model.localized("Име", "Name"), text: Binding(
                                get: { deviceProfiles[entity.entityId]?.name ?? "" },
                                set: { deviceProfiles[entity.entityId, default: .empty].name = $0 }
                            ))
                            TextField("mdi:icon", text: Binding(
                                get: { deviceProfiles[entity.entityId]?.icon ?? "" },
                                set: { deviceProfiles[entity.entityId, default: .empty].icon = $0 }
                            ))
                            Picker(model.localized("Изглед", "Layout"), selection: Binding(
                                get: { deviceProfiles[entity.entityId]?.layout ?? "compact" },
                                set: { deviceProfiles[entity.entityId, default: .empty].layout = $0 }
                            )) {
                                Text("Info").tag("info")
                                Text("Compact").tag("compact")
                                Text("Expanded").tag("expanded")
                            }
                            Picker(model.localized("Стая", "Room"), selection: Binding(
                                get: { deviceProfiles[entity.entityId]?.areaId ?? "" },
                                set: { deviceProfiles[entity.entityId, default: .empty].areaId = $0.isEmpty ? nil : $0 }
                            )) {
                                Text(model.localized("Автоматично", "Automatic")).tag("")
                                ForEach(rooms.rooms) { room in Text(room.name).tag(room.id) }
                            }
                            TextField(model.localized("Контроли (разделени със запетая)", "Controls (comma-separated)"), text: Binding(
                                get: { (deviceProfiles[entity.entityId]?.controls ?? []).joined(separator: ",") },
                                set: { deviceProfiles[entity.entityId, default: .empty].controls = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                            TextField(model.localized("Потребителски ID (със запетая)", "User IDs (comma-separated)"), text: Binding(
                                get: { (deviceProfiles[entity.entityId]?.userIds ?? []).joined(separator: ",") },
                                set: { deviceProfiles[entity.entityId, default: .empty].userIds = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                            ))
                            Button(model.localized("Запази устройството", "Save device")) {
                                Task { await saveDevice(entity.entityId) }
                            }
                        }
                    }
                }
            }
            Button(model.localized("Обнови мениджърите", "Refresh managers")) {
                Task { await load() }
            }
        }
        .task { await load() }
    }
}
