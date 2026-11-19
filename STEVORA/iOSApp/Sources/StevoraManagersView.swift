import SwiftUI

/// Live, server-authorized manager. No local admin flag grants access.
struct StevoraManagersView: View {
    @ObservedObject var model: StevoraModel
    @State private var rooms: StevoraAdminAPI.RoomSnapshot?
    @State private var assistants: StevoraAdminAPI.AssistantSnapshot?
    @State private var selectedDefault = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private func gateway() -> StevoraAssistantGateway {
        StevoraAssistantGateway(address: model.address, token: model.token)
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
            assistants = try JSONDecoder().decode(StevoraAdminAPI.AssistantSnapshot.self, from: assistantData)
            selectedDefault = assistants?.settings.defaultPipeline ?? ""
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

    private func saveAssistant() async {
        guard let assistants else { return }
        do {
            _ = try await gateway().adminRequest("stevora/admin/assistants/update", fields: [
                "expected_revision": assistants.revision,
                "default_pipeline": selectedDefault.isEmpty ? NSNull() : selectedDefault as Any,
                "user_pipelines": assistants.settings.userPipelines
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
