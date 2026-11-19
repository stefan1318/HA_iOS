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
        case assistantsResolve = "stevora/assistants/resolve"
    }

    struct Capabilities: Decodable {
        let roomManager: Bool
        let assistantManager: Bool

        enum CodingKeys: String, CodingKey {
            case roomManager = "room_manager"
            case assistantManager = "assistant_manager"
        }
    }

    struct AssistantPipeline: Decodable, Equatable {
        let id: String
        let name: String
    }

    struct AssistantSettings: Codable {
        let defaultPipeline: String?
        let userPipelines: [String: String]
        enum CodingKeys: String, CodingKey {
            case defaultPipeline = "default_pipeline"
            case userPipelines = "user_pipelines"
        }
    }

    struct AssistantResolution: Decodable {
        let pipelineId: String?
        let source: String
        enum CodingKeys: String, CodingKey {
            case pipelineId = "pipeline_id"
            case source
        }
    }

    static func updateAssistants(id: Int, expectedRevision: Int, settings: AssistantSettings) -> [String: Any] {
        [
            "id": id,
            "type": Command.assistantsUpdate.rawValue,
            "expected_revision": expectedRevision,
            "default_pipeline": settings.defaultPipeline as Any? ?? NSNull(),
            "user_pipelines": settings.userPipelines
        ]
    }

    struct RoomSnapshot: Decodable {
        struct Room: Decodable, Identifiable {
            let id: String
            let name: String
        }
        struct Entity: Decodable, Identifiable {
            let entityId: String
            let name: String
            let included: Bool
            let disabled: Bool
            let hidden: Bool
            var id: String { entityId }
            enum CodingKeys: String, CodingKey {
                case entityId = "entity_id"
                case name, included, disabled, hidden
            }
        }
        let revision: Int
        let rooms: [Room]
        let entities: [Entity]
        let visibility: [String: String]
        let roomAliases: [String: String]
        let entityAliases: [String: String]
        let roomOrder: [String]
        enum CodingKeys: String, CodingKey {
            case revision, rooms, entities, visibility
            case roomAliases = "room_aliases"
            case entityAliases = "entity_aliases"
            case roomOrder = "room_order"
        }
    }

    struct AssistantUser: Decodable, Identifiable {
        let id: String
        let name: String
    }

    struct AssistantSnapshot: Decodable {
        let users: [AssistantUser]

        let revision: Int
        let settings: AssistantSettings
        let pipelines: [AssistantPipeline]
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

    static func decodeResult<T: Decodable>(_ response: [String: Any], as type: T.Type) throws -> T {
        guard response["success"] as? Bool == true,
              let result = response["result"],
              JSONSerialization.isValidJSONObject(result) else { throw AdminError.unavailable }
        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(T.self, from: data)
    }

    enum AdminError: Error { case unavailable }

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
