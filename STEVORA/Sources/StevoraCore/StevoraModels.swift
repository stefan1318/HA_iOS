import Foundation

public enum StevoraSection: String, CaseIterable, Codable, Sendable {
    case home
    case rooms
    case climate
    case lighting
    case automations
    case settings

    public func title(language: StevoraLanguage) -> String {
        switch (self, language) {
        case (.home, .bulgarian): "Начало"
        case (.rooms, .bulgarian): "Стаи"
        case (.climate, .bulgarian): "Климат"
        case (.lighting, .bulgarian): "Осветление"
        case (.automations, .bulgarian): "Автоматизации"
        case (.settings, .bulgarian): "Настройки"
        case (.home, .english): "Home"
        case (.rooms, .english): "Rooms"
        case (.climate, .english): "Climate"
        case (.lighting, .english): "Lighting"
        case (.automations, .english): "Automations"
        case (.settings, .english): "Settings"
        }
    }
}

public enum StevoraLanguage: String, Codable, Sendable {
    case bulgarian = "bg"
    case english = "en"
}

public enum StevoraConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

public struct StevoraServer: Equatable, Sendable {
    public let baseURL: URL

    public init?(address: String) {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        self.baseURL = url
    }

    public func apiURL(path: String) -> URL? {
        guard path.hasPrefix("/api/"), !path.hasPrefix("//") else { return nil }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.scheme == baseURL.scheme, url.host == baseURL.host,
              url.port == baseURL.port else { return nil }
        return url
    }
}

public struct StevoraEntityState: Codable, Equatable, Sendable {
    public let entityId: String
    public let state: String
    public let friendlyName: String?

    public init(entityId: String, state: String, friendlyName: String? = nil) {
        self.entityId = entityId
        self.state = state
        self.friendlyName = friendlyName
    }
}
