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
