import Foundation

/// Client-side request/response contract for server-enforced STEVORA administration.
/// The server must verify the authenticated Home Assistant user is an administrator.
enum StevoraAdminAPI {
    enum Command: String {
        case capabilities = "stevora/admin/capabilities"
        case roomsGet = "stevora/admin/rooms/get"
        case roomsUpdate = "stevora/admin/rooms/update"
        case assistantsGet = "stevora/admin/assistants/get"
        case assistantsUpdate = "stevora/admin/assistants/update"
    }

    struct Capabilities: Decodable {
        let roomManager: Bool
        let assistantManager: Bool

        enum CodingKeys: String, CodingKey {
            case roomManager = "room_manager"
            case assistantManager = "assistant_manager"
        }
    }

    struct VisibilityPatch: Encodable {
        let entityId: String
        let visibility: Visibility

        enum Visibility: String, Encodable {
            case automatic = "default"
            case include
            case exclude
        }

        enum CodingKeys: String, CodingKey {
            case entityId = "entity_id"
            case visibility
        }
    }

    static func request(id: Int, command: Command) -> [String: Any] {
        ["id": id, "type": command.rawValue]
    }

    static func updateVisibility(id: Int, expectedRevision: Int, patches: [VisibilityPatch]) throws -> [String: Any] {
        let encoded = try JSONEncoder().encode(patches)
        let values = try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]] ?? []
        return [
            "id": id,
            "type": Command.roomsUpdate.rawValue,
            "expected_revision": expectedRevision,
            "entities": values
        ]
    }

    /// Do not enable admin UI merely because a manifest exists.
    /// The authenticated server must explicitly authorize each command.
    static func isForbidden(_ response: [String: Any]) -> Bool {
        guard response["success"] as? Bool == false,
              let error = response["error"] as? [String: Any] else { return false }
        return (error["code"] as? String) == "unauthorized" ||
               (error["code"] as? String) == "forbidden"
    }
}
