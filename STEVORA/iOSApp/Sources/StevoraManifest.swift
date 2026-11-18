import Foundation

/// Read-only, optional STEVORA Home Hub discovery response.
/// Never replace native Home Assistant discovery or widen user permissions.
struct StevoraManifest: Decodable, Equatable {
    struct Room: Decodable, Equatable {
        let id: String
        let name: String
    }
    let schemaVersion: String
    let installationId: String
    let revision: Int
    let rooms: [Room]
    let mappings: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case installationId = "installation_id"
        case revision, rooms, mappings
    }
}
