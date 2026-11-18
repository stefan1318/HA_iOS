import Foundation

/// The host app supplies its existing authenticated Home Assistant WebSocket session.
public protocol StevoraWebSocketTransport {
    func request(_ message: [String: Any]) async throws -> Data
}

public enum StevoraSyncResult {
    case updated(StevoraManifest)
    case unchanged
    case nativeHomeAssistantFallback
}

@MainActor
public final class StevoraSyncCoordinator {
    private let transport: StevoraWebSocketTransport
    private var cached: StevoraManifest?

    public init(transport: StevoraWebSocketTransport) {
        self.transport = transport
    }

    /// Invoke after HA connection, reconnection or explicit refresh.
    /// Never performs device control or writes configuration.
    public func refresh() async -> StevoraSyncResult {
        do {
            let data = try await transport.request(StevoraManifestSync.request(id: 1))
            guard let manifest = try StevoraManifestSync.parseResponse(data) else {
                return .nativeHomeAssistantFallback
            }
            if cached?.installationId == manifest.installationId &&
                cached?.revision == manifest.revision {
                return .unchanged
            }
            cached = manifest
            return .updated(manifest)
        } catch {
            return .nativeHomeAssistantFallback
        }
    }

    public func clearOnServerChange() { cached = nil }
}
