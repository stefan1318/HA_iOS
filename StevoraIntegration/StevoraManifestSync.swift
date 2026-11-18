import Foundation

/// Adapter for an already authenticated Home Assistant WebSocket transport.
/// The host app must send requests over its existing OAuth-authorized HA connection.
public struct StevoraManifest: Codable, Equatable {
    public struct Room: Codable, Equatable {
        public let id: String
        public let name: String
    }

    public let schemaVersion: String
    public let installationId: String
    public let preferredLanguage: String
    public let rooms: [Room]
    public let mappings: [String: [String]]
    public let revision: Int

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case installationId = "installation_id"
        case preferredLanguage = "preferred_language"
        case rooms, mappings, revision
    }
}

public enum StevoraManifestSync {
    public static let requestType = "stevora/manifest"

    public static func request(id: Int) -> [String: Any] {
        ["id": id, "type": requestType]
    }

    public static func parseResponse(_ data: Data) throws -> StevoraManifest? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.success, let result = response.result,
              result.schemaVersion == "1.0" else { return nil }
        return result
    }

    private struct Response: Decodable {
        let success: Bool
        let result: StevoraManifest?
    }
}
