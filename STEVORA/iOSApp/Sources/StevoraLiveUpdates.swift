import Foundation

/// Home Assistant WebSocket event stream. A single connection delivers state changes
/// as they happen, instead of polling the REST API on a fixed timer.
@MainActor
final class StevoraLiveUpdates {
    private var socket: URLSessionWebSocketTask?
    private var worker: Task<Void, Never>?
    private var generation = 0

    func start(address: String, token: String, onChange: @escaping @MainActor (HAEntity) -> Void,
               onReconnect: @escaping @MainActor () async -> Void) {
        stop()
        generation += 1
        let current = generation
        worker = Task { [weak self] in
            var delay: UInt64 = 1
            while !Task.isCancelled {
                guard let self, current == self.generation else { return }
                do {
                    try await self.listen(address: address, token: token, onChange: onChange)
                    delay = 1
                } catch {
                    // A temporary loss of network connectivity is expected on mobile.
                }
                guard !Task.isCancelled, current == self.generation else { return }
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
                guard !Task.isCancelled, current == self.generation else { return }
                await onReconnect()
            }
        }
    }

    func stop() {
        generation += 1
        worker?.cancel()
        worker = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func listen(address: String, token: String,
                        onChange: @escaping @MainActor (HAEntity) -> Void) async throws {
        guard var parts = URLComponents(string: address),
              parts.scheme?.lowercased() == "https", parts.host != nil,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw HAError.invalidURL }
        parts.scheme = "wss"
        parts.path = (parts.path.hasSuffix("/") ? String(parts.path.dropLast()) : parts.path) + "/api/websocket"
        guard let url = parts.url else { throw HAError.invalidURL }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
            if socket === task { socket = nil }
        }

        var authenticated = false
        var subscribed = false
        while !Task.isCancelled {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .string(let value): data = Data(value.utf8)
            case .data(let value): data = value
            @unknown default: continue
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            switch type {
            case "auth_required":
                try await send(["type": "auth", "access_token": token], on: task)
            case "auth_ok":
                authenticated = true
                try await send(["id": 1, "type": "subscribe_events", "event_type": "state_changed"], on: task)
            case "auth_invalid":
                throw HAError.unauthorized
            case "result":
                if let id = json["id"] as? Int, id == 1 {
                    guard authenticated, json["success"] as? Bool == true else {
                        throw HAError.unexpectedResponse
                    }
                    subscribed = true
                }
            case "event":
                guard subscribed,
                      let event = json["event"] as? [String: Any],
                      let payload = event["data"] as? [String: Any],
                      let newState = payload["new_state"] as? [String: Any] else { continue }
                let stateData = try JSONSerialization.data(withJSONObject: newState)
                if let entity = try? JSONDecoder().decode(HAEntity.self, from: stateData) {
                    onChange(entity)
                }
            default: break
            }
        }
    }

    private func send(_ object: [String: Any], on task: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }
}
