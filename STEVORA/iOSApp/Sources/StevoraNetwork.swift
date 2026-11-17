import Foundation
import Security

struct HAEntity: Decodable, Identifiable {
    struct Attributes: Decodable {
        let friendly_name: String?
        let temperature: Double?
        let current_temperature: Double?
        let unit_of_measurement: String?
        let brightness: Int?
        let rgb_color: [Int]?
    }
    let entity_id: String
    let state: String
    let attributes: Attributes
    var id: String { entity_id }
    var domain: String { entity_id.components(separatedBy: ".").first ?? "" }
    var name: String { attributes.friendly_name ?? entity_id }
}

enum HAError: LocalizedError {
    case invalidURL, unauthorized, unexpectedResponse, insecureConnection
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid server URL"
        case .unauthorized: "Authentication failed (401)"
        case .unexpectedResponse: "Server returned an unexpected response"
        case .insecureConnection: "Use an HTTPS server URL"
        }
    }
}

enum CredentialStore {
    private static let service = "com.stevora.companion.ios"
    static func save(_ value: String, key: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: service,
                                     kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
    static func read(key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: service,
                                     kSecAttrAccount as String: key,
                                     kSecReturnData as String: true,
                                     kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: key] as CFDictionary)
    }
}

struct HAClient {
    let baseURL: URL
    let token: String

    init(address: String, token: String) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw HAError.insecureConnection }
        baseURL = url
        self.token = token
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard path.hasPrefix("/api/"), !path.hasPrefix("//"),
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.host == baseURL.host else { throw HAError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HAError.unexpectedResponse }
        if http.statusCode == 401 { throw HAError.unauthorized }
        guard (200...299).contains(http.statusCode) else { throw HAError.unexpectedResponse }
        return data
    }

    func check() async throws {
        _ = try await request("/api/")
    }

    func states() async throws -> [HAEntity] {
        let data = try await request("/api/states")
        return try JSONDecoder().decode([HAEntity].self, from: data)
    }

    func service(domain: String, action: String, entityID: String, extra: [String: Any] = [:]) async throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        guard !domain.isEmpty, !action.isEmpty,
              domain.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              action.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              entityID.hasPrefix(domain + ".") else { throw HAError.invalidURL }
        var payload = extra
        payload["entity_id"] = entityID
        let data = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("/api/services/\(domain)/\(action)", method: "POST", body: data)
    }
}
