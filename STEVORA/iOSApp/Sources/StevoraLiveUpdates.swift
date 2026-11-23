import Foundation

/// Home Assistant WebSocket event stream. A single connection delivers state changes
/// as they happen, instead of polling the REST API on a fixed timer.
@MainActor
final class StevoraLiveUpdates {
    private var socket: URLSessionWebSocketTask?
    private var worker: Task<Void, Never>?
    private var generation = 0

    func start(address: String, token: String, language: String = "bg", allowLocalHTTP: Bool = false, onChange: @escaping @MainActor (HAEntity) -> Void,
               onRemove: @escaping @MainActor (String) -> Void,
               onReady: @escaping @MainActor () -> Void,
               onUser: @escaping @MainActor ([String: Any]) -> Void,
               onLanguage: @escaping @MainActor (String) -> Void,
               onReconnect: @escaping @MainActor () async -> Void,
               onAuthExpired: @escaping @MainActor () async -> Void,
               onManifest: @escaping @MainActor (StevoraManifest?) -> Void) {
        stop()
        generation += 1
        let current = generation
        worker = Task { [weak self] in
            var delay: UInt64 = 1
            while !Task.isCancelled {
                guard let self, current == self.generation else { return }
                do {
                    try await self.listen(address: address, token: token, language: language, allowLocalHTTP: allowLocalHTTP, onChange: onChange, onRemove: onRemove, onReady: onReady, onUser: onUser, onLanguage: onLanguage, onManifest: onManifest)
                    delay = 1
                } catch HAError.unauthorized {
                    guard !Task.isCancelled, current == self.generation else { return }
                    await onAuthExpired()
                    return
                } catch {
                    // A temporary loss of network connectivity is expected on mobile.
                }
                guard !Task.isCancelled, current == self.generation else { return }
                await onReconnect()
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
                guard !Task.isCancelled, current == self.generation else { return }
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

    private func listen(address: String, token: String, language: String, allowLocalHTTP: Bool,
                        onChange: @escaping @MainActor (HAEntity) -> Void,
                        onRemove: @escaping @MainActor (String) -> Void,
               onReady: @escaping @MainActor () -> Void,
               onUser: @escaping @MainActor ([String: Any]) -> Void,
               onLanguage: @escaping @MainActor (String) -> Void,
                        onManifest: @escaping @MainActor (StevoraManifest?) -> Void) async throws {
        guard let baseURL = URL(string: address),
              StevoraTransportPolicy.permits(baseURL, allowLocalHTTP: allowLocalHTTP),
              var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw HAError.insecureConnection }
        parts.scheme = baseURL.scheme?.lowercased() == "http" ? "ws" : "wss"
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
        var requestID = 4
        var profileLoaded = false
        var manifestLanguage = language
        var fetchingManifest = false
        var manifestDirty = false
        func requestManifest() async throws {
            guard profileLoaded else { return }
            if fetchingManifest {
                manifestDirty = true
                return
            }
            fetchingManifest = true
            manifestDirty = false
            requestID += 1
            try await send(["id": requestID, "type": "stevora/os/v1/manifest", "language": manifestLanguage == "en" ? "en" : "bg"], on: task)
        }
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
            guard !Task.isCancelled, socket === task else { return }
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
                    onReady()
                    try await send(["id": 2, "type": "stevora/os/v1/manifest/subscribe"], on: task)
                    try await send(["id": 3, "type": "auth/current_user"], on: task)
                    try await send(["id": 4, "type": "frontend/get_user_data", "key": "stevora_profile"], on: task)
                } else if json["id"] as? Int == 4 {
                    if let result = json["result"] as? [String: Any], let value = result["value"] as? [String: Any],
                       let preferred = value["language"] as? String, ["en", "bg"].contains(preferred) {
                        manifestLanguage = preferred
                        onLanguage(preferred)
                    }
                    profileLoaded = true
                    try await requestManifest()
                } else if json["id"] as? Int == 3, let user = json["result"] as? [String: Any] {
                    onUser(user)
                } else if let id = json["id"] as? Int, id == requestID, fetchingManifest {
                    fetchingManifest = false
                    if json["success"] as? Bool == true,
                       let payload = json["result"], JSONSerialization.isValidJSONObject(payload),
                       let data = try? JSONSerialization.data(withJSONObject: payload),
                       let manifest = try? JSONDecoder().decode(StevoraManifest.self, from: data) {
                        onManifest(manifest)
                    } else {
                        onManifest(nil)
                    }
                    if manifestDirty { try await requestManifest() }
                }
            case "event":
                if json["id"] as? Int == 2 {
                    try await requestManifest()
                    continue
                }
                guard subscribed,
                      let event = json["event"] as? [String: Any],
                      let payload = event["data"] as? [String: Any] else { continue }
                guard let newState = payload["new_state"] as? [String: Any] else {
                    if payload["new_state"] is NSNull, let id = payload["entity_id"] as? String { onRemove(id) }
                    continue
                }
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
