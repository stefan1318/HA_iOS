import SwiftUI

/// This separate simulator app exercises the production views with a synthetic home.
@main
struct SettingsFixtureApp: App {
    @StateObject private var model: StevoraModel

    init() {
        let env = ProcessInfo.processInfo.environment
        let model = StevoraModel()
        model.language = env["TEST_LANGUAGE"] ?? "en"
        model.connected = true
        model.liveConnected = env["TEST_ROLE"] != "offline"
        model.receiveUser(["id": "tester", "name": "Test account", "is_admin": env["TEST_ROLE"] != "member"])
        let data = (1...500).map { index in
            ["entity_id": "scene.fixture_\(index)", "state": "ready",
             "attributes": ["friendly_name": "Scene \(index)"]] as [String: Any]
        }
        model.entities = try! JSONDecoder().decode([HAEntity].self, from: JSONSerialization.data(withJSONObject: data))
        let ids = model.entities.map(\.id)
        let manifest = StevoraManifest(controllable: [], entities: [], schemaVersion: "1.0", installationId: "test",
            revision: 1, rooms: [.init(id: "room", name: "Fixture room")], mappings: ["room": ids])
        model.receiveManifest(manifest)
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup { RootView().environmentObject(model) }
    }
}
