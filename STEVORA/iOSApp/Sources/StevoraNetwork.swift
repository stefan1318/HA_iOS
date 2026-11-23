import Foundation
import Security
import CoreLocation
import UIKit

struct HAEntity: Decodable, Identifiable {
    struct Attributes: Decodable {
        let friendly_name: String?
        let device_class: String?
        let temperature: Double?
        let current_temperature: Double?
        let unit_of_measurement: String?
        let brightness: Int?
        let rgb_color: [Int]?
        let hvac_modes: [String]?
        let fan_modes: [String]?
        let fan_mode: String?
        let preset_modes: [String]?
        let preset_mode: String?
        let min_temp: Double?
        let max_temp: Double?
        let supported_color_modes: [String]?
        let color_temp_kelvin: Int?
        let min_color_temp_kelvin: Int?
        let max_color_temp_kelvin: Int?
        let current_position: Int?
        let current_tilt_position: Int?
        let percentage: Int?
        let direction: String?
        let oscillating: Bool?
        let swing_modes: [String]?
        let source_list: [String]?
        let volume_level: Double?
        let color_mode: String?
        let effect_list: [String]?
        let effect: String?
    }
    let entity_id: String
    let state: String
    let attributes: Attributes
    var id: String { entity_id }
    var domain: String { entity_id.components(separatedBy: ".").first ?? "" }
    var name: String { attributes.friendly_name ?? entity_id }
}

enum HAError: LocalizedError {
    case invalidURL, unauthorized, unexpectedResponse, insecureConnection, registrationExpired
    var errorDescription: String? {
        switch self {
        case .registrationExpired: "Mobile App registration expired"
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

/// Plain HTTP is opt-in and limited to literal RFC1918 IPv4 hosts.
enum StevoraTransportPolicy {
    static func permits(_ url: URL, allowLocalHTTP: Bool) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return false }
        if scheme == "https" { return true }
        guard scheme == "http", allowLocalHTTP else { return false }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        var values: [Int] = []
        for octet in octets {
            guard !octet.isEmpty, octet.count <= 3,
                  octet.allSatisfy({ $0.isASCII && $0.isNumber }),
                  (octet.count == 1 || octet.first != "0"),
                  let value = Int(octet), (0...255).contains(value) else { return false }
            values.append(value)
        }
        return values[0] == 10 ||
            (values[0] == 172 && (16...31).contains(values[1])) ||
            (values[0] == 192 && values[1] == 168)
    }
}

struct HAClient {
    let baseURL: URL
    let token: String

    init(address: String, token: String, allowLocalHTTP: Bool = false) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              StevoraTransportPolicy.permits(url, allowLocalHTTP: allowLocalHTTP) else { throw HAError.insecureConnection }
        baseURL = url
        self.token = token
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true) async throws -> Data {
        guard path.hasPrefix("/api/"), !path.hasPrefix("//"),
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.scheme == baseURL.scheme,
              url.host == baseURL.host,
              url.port == baseURL.port else { throw HAError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if authenticated { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await StevoraNoRedirect.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HAError.unexpectedResponse }
        if http.statusCode == 410 && !authenticated { throw HAError.registrationExpired }
        if http.statusCode == 401 { throw HAError.unauthorized }
        guard (200...299).contains(http.statusCode) else { throw HAError.unexpectedResponse }
        return data
    }

    @MainActor
    func registerPresence(deviceID: String) async throws -> String {
        let device = UIDevice.current
        let fields = ["app_id": Bundle.main.bundleIdentifier ?? "com.stevora.companion.ios",
                      "app_name": "STEVORA", "device_id": deviceID, "device_name": "STEVORA " + device.model,
                      "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1",
                      "manufacturer": "Apple", "model": device.model, "os_name": device.systemName, "os_version": device.systemVersion]
        let data = try await request("/api/mobile_app/registrations", method: "POST",
                                     body: JSONEncoder().encode(fields))
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let webhook = result["webhook_id"] as? String, validWebhook(webhook) else { throw HAError.unexpectedResponse }
        return webhook
    }

    private func validWebhook(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    func sendPresence(_ fix: CLLocation, webhook: String) async throws {
        guard validWebhook(webhook) else { throw HAError.unexpectedResponse }
        let location: [String: Any] = ["gps": [fix.coordinate.latitude, fix.coordinate.longitude],
                                       "gps_accuracy": Int(fix.horizontalAccuracy.rounded(.up))]
        let body = try JSONSerialization.data(withJSONObject: ["type": "update_location", "data": location])
        let data = try await request("/api/webhook/" + webhook, method: "POST", body: body, authenticated: false)
        if !data.isEmpty {
            guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  reply["success"] as? Bool != false else { throw HAError.unexpectedResponse }
        }
    }

    func check() async throws {
        _ = try await request("/api/")
    }

    func states() async throws -> [HAEntity] {
        let data = try await request("/api/states")
        // Third-party integrations can publish vendor attributes of arbitrary types.
        // Skip an incompatible record without losing every other room and device.
        return try JSONDecoder().decode([StateRecord].self, from: data).compactMap(\.entity)
    }

    private struct StateRecord: Decodable {
        let entity: HAEntity?

        init(from decoder: Decoder) {
            entity = try? HAEntity(from: decoder)
        }
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
