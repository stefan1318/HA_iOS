import Foundation
import SwiftUI

@MainActor
final class StevoraModel: ObservableObject {
    private let liveUpdates = StevoraLiveUpdates()
    private let oauth = StevoraOAuth()
    @Published var isOAuthSession = false
    @Published var selectedRoom = "all"
    @Published var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "stevora.favorites") ?? [])
    @Published var address = UserDefaults.standard.string(forKey: "stevora.address") ?? ""
    @Published var token = ""
    @Published var connected = false
    @Published var liveConnected = false
    @Published var busy = false
    @Published var error: String?
    @Published var entities: [HAEntity] = []
    @Published var language: String = UserDefaults.standard.string(forKey: "stevora.language") ?? "bg"

    init() {
        if let saved = CredentialStore.read(key: "access_token"), !address.isEmpty {
            token = saved
            isOAuthSession = CredentialStore.read(key: "refresh_token") != nil
            Task { await connect(persist: false) }
        }
    }

    func localized(_ bg: String, _ en: String) -> String { language == "bg" ? bg : en }

    private func client() throws -> HAClient {
        try HAClient(address: address, token: token)
    }

    func signIn() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let url = try HAClient(address: address, token: "temporary").baseURL
            let auth = try await oauth.authorizationCode(server: url)
            let tokens = try await StevoraTokenAPI.exchange(server: url, code: auth.code, verifier: auth.verifier)
            guard CredentialStore.save(tokens.access_token, key: "access_token") else { throw HAError.unexpectedResponse }
            if let refresh = tokens.refresh_token {
                guard CredentialStore.save(refresh, key: "refresh_token") else { throw HAError.unexpectedResponse }
            }
            token = tokens.access_token
            isOAuthSession = true
            UserDefaults.standard.set(address, forKey: "stevora.address")
        } catch {
            self.error = error.localizedDescription
            return
        }
        busy = false
        await connect(persist: false)
    }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: "stevora.favorites")
    }

    func connect(persist: Bool = true) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            var api = try client()
            do {
                try await api.check()
            } catch HAError.unauthorized {
                guard let refresh = CredentialStore.read(key: "refresh_token") else { throw HAError.unauthorized }
                let renewed = try await StevoraTokenAPI.refresh(server: api.baseURL, token: refresh)
                guard CredentialStore.save(renewed.access_token, key: "access_token") else { throw HAError.unexpectedResponse }
                if let next = renewed.refresh_token {
                    guard CredentialStore.save(next, key: "refresh_token") else { throw HAError.unexpectedResponse }
                }
                token = renewed.access_token
                api = try client()
                try await api.check()
            }
            let loaded = try await api.states()
            if persist && !CredentialStore.save(token, key: "access_token") {
                throw NSError(domain: "STEVORA", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not securely store access token"])
            }
            UserDefaults.standard.set(address, forKey: "stevora.address")
            entities = loaded
            connected = true
            liveConnected = false
            liveUpdates.start(address: address, token: token, onChange: { [weak self] entity in
                guard let self, self.connected else { return }
                self.liveConnected = true
                if let index = self.entities.firstIndex(where: { $0.id == entity.id }) {
                    self.entities[index] = entity
                } else {
                    self.entities.append(entity)
                }
            }, onReconnect: { [weak self] in
                self?.liveConnected = false
                await self?.refresh()
            })
        } catch {
            liveUpdates.stop()
            connected = false
            liveConnected = false
            self.error = error.localizedDescription
        }
    }

    func refresh() async {
        guard connected else { return }
        do { entities = try await client().states(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func toggle(_ entity: HAEntity) async {
        guard ["light", "switch", "fan"].contains(entity.domain) else { return }
        do {
            try await client().service(domain: entity.domain,
                                       action: entity.state == "on" ? "turn_off" : "turn_on",
                                       entityID: entity.id)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setTemperature(_ entity: HAEntity, value: Double) async {
        guard entity.domain == "climate" else { return }
        do {
            try await client().service(domain: "climate", action: "set_temperature",
                                       entityID: entity.id, extra: ["temperature": value])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setBrightness(_ entity: HAEntity, value: Double) async {
        guard entity.domain == "light" else { return }
        do {
            try await client().service(domain: "light", action: "turn_on",
                                       entityID: entity.id, extra: ["brightness_pct": Int(value)])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func runRoutine(_ entity: HAEntity) async {
        guard ["scene", "script", "automation"].contains(entity.domain) else { return }
        do {
            let action = entity.domain == "automation" ? "trigger" : "turn_on"
            try await client().service(domain: entity.domain, action: action, entityID: entity.id)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setLanguage(_ newValue: String) {
        language = newValue
        UserDefaults.standard.set(newValue, forKey: "stevora.language")
    }

    func logout() {
        liveUpdates.stop()
        CredentialStore.delete(key: "access_token")
        CredentialStore.delete(key: "refresh_token")
        isOAuthSession = false
        token = ""
        connected = false
        liveConnected = false
        entities = []
        error = nil
    }
}
