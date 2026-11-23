import Foundation

/// Read-only, optional STEVORA Home Hub discovery response.
/// Never replace native Home Assistant discovery or widen user permissions.
struct StevoraManifest: Decodable, Equatable {
    struct Room: Decodable, Equatable {
        let id: String
        let name: String
    }
    struct Device: Decodable, Equatable {
        let entityId: String
        let name: String
        let layout: String?
        let controls: Set<String>?
        let availableControls: Set<String>?
        enum CodingKeys: String, CodingKey {
            case entityId = "entity_id", availableControls = "available_controls"
            case name, layout, controls
        }
    }
    func permits(_ action: String, entityID: String) -> Bool {
        guard controllable?.contains(entityID) == true,
              let device = entities?.first(where: { $0.entityId == entityID }),
              device.layout != "info", device.availableControls?.contains(action) == true else { return false }
        return device.controls?.contains(action) ?? true
    }

    let controllable: Set<String>?
    let entities: [Device]?
    let schemaVersion: String
    let installationId: String
    let revision: Int
    let rooms: [Room]
    let mappings: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case installationId = "installation_id"
        case controllable = "controllable_entities"
        case revision, rooms, mappings, entities
    }
}
