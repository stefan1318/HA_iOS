import Foundation

/// Bridge for the host app's existing authenticated WebSocket connection callbacks.
@MainActor
public final class StevoraConnectionLifecycle {
    private let coordinator: StevoraSyncCoordinator
    private let onManifest: (StevoraManifest) -> Void
    private let onFallback: () -> Void

    public init(
        coordinator: StevoraSyncCoordinator,
        onManifest: @escaping (StevoraManifest) -> Void,
        onFallback: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.onManifest = onManifest
        self.onFallback = onFallback
    }

    public func onConnected() async {
        switch await coordinator.refresh() {
        case let .updated(manifest): onManifest(manifest)
        case .nativeHomeAssistantFallback: onFallback()
        case .unchanged: break
        }
    }

    public func onDisconnected() { /* Retain cached configuration until reconnect. */ }
    public func onServerChanged() {
        coordinator.clearOnServerChange()
        onFallback()
    }
}
