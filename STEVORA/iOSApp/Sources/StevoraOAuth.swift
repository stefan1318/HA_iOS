import Foundation
import AuthenticationServices
import CryptoKit
import UIKit
import Security

/// Home Assistant authorization-code flow with PKCE. No user password enters STEVORA.
@MainActor
final class StevoraOAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated static let clientID = "https://raw.githubusercontent.com/stefan1318/HA_iOS/e1081cb7f86006eb1d11b8bca336c7247e245b0b/STEVORA/oauth/ios-client.html"
    nonisolated static let redirectURI = "com.stevora://auth/callback"
    private var session: ASWebAuthenticationSession?

    func authorizationCode(server: URL) async throws -> (code: String, verifier: String) {
        let verifier = Self.randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents(url: server.appendingPathComponent("auth/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else { throw HAError.invalidURL }
        defer { session = nil }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "com.stevora") { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? HAError.unauthorized) }
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            self.session = auth
            if !auth.start() {
                self.session = nil
                continuation.resume(throwing: HAError.unexpectedResponse)
            }
        }
        guard callback.scheme == "com.stevora", callback.host == "auth",
              callback.path == "/callback",
              let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw HAError.unauthorized
        }
        return (code, verifier)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct StevoraTokens: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
}

enum StevoraTokenAPI {
    static func exchange(server: URL, code: String, verifier: String) async throws -> StevoraTokens {
        try await request(server: server, fields: [
            "grant_type": "authorization_code", "code": code,
            "client_id": StevoraOAuth.clientID,
            "code_verifier": verifier,
            "redirect_uri": StevoraOAuth.redirectURI
        ])
    }

    static func refresh(server: URL, token: String, clientID: String) async throws -> StevoraTokens {
        try await request(server: server, fields: [
            "grant_type": "refresh_token", "refresh_token": token,
            "client_id": clientID
        ])
    }

    private static func request(server: URL, fields: [String: String]) async throws -> StevoraTokens {
        var request = URLRequest(url: server.appendingPathComponent("auth/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await StevoraNoRedirect.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw HAError.unauthorized
        }
        return try JSONDecoder().decode(StevoraTokens.self, from: data)
    }
}
