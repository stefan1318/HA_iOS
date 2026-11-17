import Foundation

/// Account-bound Assist routing, exactly matching STEVORA Android 2.1.
/// Never route a panel/user through the admin conversation agent.
struct StevoraAssistantRoute {
    let pipelineID: String
    let pipelineName: String
    let accountName: String
    let isAdmin: Bool
    let supportsSTT: Bool
    var roleLabel: String { isAdmin ? "ADMIN" : "USER / PANEL" }
}

enum StevoraAssistantError: LocalizedError {
    case disconnected, authentication, invalidResponse, noMatchingPipeline(String), ambiguousPipeline(String)
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .disconnected: return "No secure STEVORA Home Hub connection."
        case .authentication: return "Unable to authenticate the current Home Hub account."
        case .invalidResponse: return "Invalid Assist pipeline response from Home Hub."
        case .noMatchingPipeline(let agent): return "No Assist pipeline configured for \(agent). Check Home Assistant settings."
        case .ambiguousPipeline(let agent): return "Multiple Assist pipelines use \(agent). Select one in Home Assistant."
        case .remote(let message): return message
        }
    }
}

actor StevoraAssistantGateway {
    private let address: String
    private let token: String
    private var socket: URLSessionWebSocketTask?
    private var nextID = 1

    init(address: String, token: String) {
        self.address = address
        self.token = token
    }

    private func send(_ object: [String: Any]) async throws {
        guard let socket else { throw StevoraAssistantError.disconnected }
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: bytes, as: UTF8.self)))
    }

    private func receive() async throws -> [String: Any] {
        guard let socket else { throw StevoraAssistantError.disconnected }
        let response = try await socket.receive()
        let data: Data
        switch response {
        case .string(let value): data = Data(value.utf8)
        case .data(let value): data = value
        @unknown default: throw StevoraAssistantError.invalidResponse
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StevoraAssistantError.invalidResponse
        }
        return object
    }

    private func connect() async throws {
        guard var parts = URLComponents(string: address),
              parts.scheme?.lowercased() == "https", parts.host != nil,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else {
            throw StevoraAssistantError.disconnected
        }
        parts.scheme = "wss"
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == ""
            ? "/api/websocket" : parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).withLeadingSlash + "/api/websocket"
        guard let url = parts.url else { throw StevoraAssistantError.disconnected }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        let hello = try await receive()
        guard hello["type"] as? String == "auth_required" else { throw StevoraAssistantError.authentication }
        try await send(["type": "auth", "access_token": token])
        let result = try await receive()
        guard result["type"] as? String == "auth_ok" else { throw StevoraAssistantError.authentication }
    }

    private func disconnect() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private func request(_ type: String, fields: [String: Any] = [:]) async throws -> [String: Any] {
        nextID += 1
        let identifier = nextID
        var command = fields
        command["id"] = identifier
        command["type"] = type
        try await send(command)
        while true {
            let message = try await receive()
            guard message["type"] as? String == "result",
                  message["id"] as? Int == identifier else { continue }
            if message["success"] as? Bool != true {
                let remote = message["error"] as? [String: Any]
                throw StevoraAssistantError.remote(remote?["message"] as? String ?? "Assist request failed.")
            }
            return message["result"] as? [String: Any] ?? [:]
        }
    }

    private func verifiedRoute() async throws -> StevoraAssistantRoute {
        let user = try await request("auth/current_user")
        guard let name = user["name"] as? String,
              user["is_admin"] as? Bool,
              user["is_owner"] as? Bool else { throw StevoraAssistantError.authentication }
        let elevated = isAdmin(user, owner: user["is_owner"] as? Bool ?? false)
        let expected = elevated
            ? "conversation.living_room_openai_conversation"
            : "conversation.openai_conversation_for_panels"
        let result = try await request("assist_pipeline/pipeline/list")
        guard let pipelines = result["pipelines"] as? [[String: Any]] else {
            throw StevoraAssistantError.invalidResponse
        }
        let matching = pipelines.filter {
            ($0["conversation_engine"] as? String)?.caseInsensitiveCompare(expected) == .orderedSame
        }
        guard !matching.isEmpty else { throw StevoraAssistantError.noMatchingPipeline(expected) }
        guard matching.count == 1 else { throw StevoraAssistantError.ambiguousPipeline(expected) }
        guard let candidate = matching.first,
              let id = candidate["id"] as? String else { throw StevoraAssistantError.invalidResponse }
        return StevoraAssistantRoute(
            pipelineID: id, pipelineName: candidate["name"] as? String ?? "STEVORA",
            accountName: name, isAdmin: elevated,
            supportsSTT: candidate["stt_engine"] as? String != nil
        )
    }

    private func isAdmin(_ user: [String: Any], owner: Bool) -> Bool {
        (user["is_admin"] as? Bool ?? false) || owner
    }

    func inspect() async throws -> StevoraAssistantRoute {
        try await connect()
        defer { disconnect() }
        return try await verifiedRoute()
    }

    func converse(text: String, conversationID: String?) async throws -> (String, String?, StevoraAssistantRoute) {
        try await connect()
        defer { disconnect() }
        let route = try await verifiedRoute()
        nextID += 1
        let identifier = nextID
        var command: [String: Any] = [
            "id": identifier, "type": "assist_pipeline/run",
            "start_stage": "intent", "end_stage": "intent",
            "pipeline": route.pipelineID, "input": ["text": text]
        ]
        if let conversationID { command["conversation_id"] = conversationID }
        try await send(command)
        var reply: String?
        var nextConversationID = conversationID
        while true {
            let message = try await receive()
            guard message["id"] as? Int == identifier else { continue }
            if message["type"] as? String == "result" {
                if message["success"] as? Bool != true {
                    let remote = message["error"] as? [String: Any]
                    throw StevoraAssistantError.remote(remote?["message"] as? String ?? "Assist pipeline failed.")
                }
                continue
            }
            guard message["type"] as? String == "event",
                  let event = message["event"] as? [String: Any],
                  let eventType = event["type"] as? String else { continue }
            let data = event["data"] as? [String: Any] ?? [:]
            if eventType == "error" {
                throw StevoraAssistantError.remote(data["message"] as? String ?? "Assist pipeline error.")
            }
            if eventType == "intent-end" {
                if let output = data["intent_output"] as? [String: Any] {
                    nextConversationID = output["conversation_id"] as? String ?? nextConversationID
                    if let response = output["response"] as? [String: Any],
                       let speech = response["speech"] as? [String: Any],
                       let plain = speech["plain"] as? [String: Any] {
                        reply = plain["speech"] as? String
                    }
                }
            }
            if eventType == "run-end" {
                return (reply ?? "Command processed.", nextConversationID, route)
            }
        }
    }
}

private extension String {
    var withLeadingSlash: String { hasPrefix("/") ? self : "/" + self }
}
