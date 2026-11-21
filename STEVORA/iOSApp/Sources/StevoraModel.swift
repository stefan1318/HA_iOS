import Foundation
import SwiftUI
import CryptoKit
import AuthenticationServices

@MainActor
final class StevoraModel: ObservableObject {
    private let liveUpdates = StevoraLiveUpdates()
    private let oauth = StevoraOAuth()
    @Published var isOAuthSession = false
    @Published var selectedRoom = "all"
    @Published var favorites: Set<String> = []
    @Published var address = UserDefaults.standard.string(forKey: "stevora.address") ?? ""
    @Published var allowLocalHTTP = UserDefaults.standard.bool(forKey: "stevora.allowLocalHTTP")
    @Published var token = ""
    @Published var connected = false
    @Published private(set) var connectionMode = "STEVORA OS"
    @Published private(set) var stevoraManifest: StevoraManifest?
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
        try HAClient(address: address, token: token, allowLocalHTTP: allowLocalHTTP)
    }

    func signIn() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let url = try HAClient(address: address, token: "temporary", allowLocalHTTP: allowLocalHTTP).baseURL
            let auth = try await oauth.authorizationCode(server: url)
            let tokens = try await StevoraTokenAPI.exchange(server: url, code: auth.code, verifier: auth.verifier)
            guard CredentialStore.save(tokens.access_token, key: "access_token") else { throw HAError.unexpectedResponse }
            if let refresh = tokens.refresh_token {
                guard CredentialStore.save(refresh, key: "refresh_token") else { throw HAError.unexpectedResponse }
            }
            UserDefaults.standard.set(StevoraOAuth.clientID, forKey: "stevora.oauth.clientID")
            token = tokens.access_token
            isOAuthSession = true
            UserDefaults.standard.set(address, forKey: "stevora.address")
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                self.error = error.localizedDescription
            }
            return
        }
        busy = false
        await connect(persist: false)
    }

    private var favoriteKey: String {
        let host = (URL(string: address)?.host ?? address).lowercased()
        let fingerprint = SHA256.hash(data: Data(token.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return "stevora.favorites.\(host).\(fingerprint)"
    }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: favoriteKey)
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
                // Previously issued refresh tokens remain bound to the original client ID.
                let clientID = UserDefaults.standard.string(forKey: "stevora.oauth.clientID") ?? "https://stevora.com"
                let renewed = try await StevoraTokenAPI.refresh(server: api.baseURL, token: refresh, clientID: clientID)
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
            favorites = Set(UserDefaults.standard.stringArray(forKey: favoriteKey) ?? [])
            connected = true
            connectionMode = "STEVORA OS"
            stevoraManifest = nil
            liveConnected = false
            liveUpdates.start(address: address, token: token, language: language, allowLocalHTTP: allowLocalHTTP, onChange: { [weak self] entity in
                guard let self, self.connected else { return }
                self.liveConnected = true
                if let index = self.entities.firstIndex(where: { $0.id == entity.id }) {
                    self.entities[index] = entity
                } else {
                    self.entities.append(entity)
                }
            }, onReady: { [weak self] in
                self?.liveConnected = true
            }, onReconnect: { [weak self] in
                self?.liveConnected = false
                self?.connectionMode = "STEVORA OS"
                self?.stevoraManifest = nil
                await self?.refresh()
            }, onManifest: { [weak self] manifest in
                self?.receiveManifest(manifest)
            })
        } catch {
            liveUpdates.stop()
            connected = false
            liveConnected = false
            connectionMode = "STEVORA OS"
            stevoraManifest = nil
            self.error = error.localizedDescription
        }
    }

    func receiveManifest(_ manifest: StevoraManifest?) {
        guard let manifest, manifest.schemaVersion == "1.0", !manifest.installationId.isEmpty else {
            stevoraManifest = nil
            connectionMode = localized("Липсва съвместим STEVORA OS манифест", "Compatible STEVORA OS manifest unavailable")
            return
        }
        if let previous = stevoraManifest,
           previous.installationId == manifest.installationId,
           previous.revision > manifest.revision { return }
        stevoraManifest = manifest
        connectionMode = "STEVORA Ecosystem"
    }

    // STEVORA owns the room and entity projection when its manifest is valid.
    // HA states supply live values only; they never expand the STEVORA device list.
    var projectedRooms: [StevoraManifest.Room] {
        stevoraManifest?.rooms ?? []
    }

    var projectedEntities: [HAEntity] {
        guard let manifest = stevoraManifest else { return [] }
        let allowed = Set(manifest.mappings.values.flatMap { $0 })
        return entities.filter { allowed.contains($0.id) }
    }

    func projectedEntities(in roomID: String) -> [HAEntity] {
        guard let manifest = stevoraManifest else { return projectedEntities }
        guard roomID != "all" else { return projectedEntities }
        let ids = Set(manifest.mappings[roomID] ?? [])
        return projectedEntities.filter { ids.contains($0.id) }
    }

    func refresh() async {
        guard connected else { return }
        do { entities = try await client().states(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func toggle(_ entity: HAEntity) async {
        guard connected && liveConnected && stevoraManifest != nil && !entity.id.lowercased().contains("backlight") else { error = "Offline or restricted device"; return }
        guard ["light", "switch", "fan"].contains(entity.domain) else { return }
        do {
            try await client().service(domain: entity.domain,
                                       action: entity.state == "on" ? "turn_off" : "turn_on",
                                       entityID: entity.id)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setTemperature(_ entity: HAEntity, value: Double) async {
        guard connected && liveConnected && stevoraManifest != nil else { error = "Offline: controls disabled"; return }
        guard entity.domain == "climate" else { return }
        do {
            try await client().service(domain: "climate", action: "set_temperature",
                                       entityID: entity.id, extra: ["temperature": value])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setClimateMode(_ entity: HAEntity, mode: String) async {
        guard connected && liveConnected && stevoraManifest != nil else { error = "Offline: controls disabled"; return }
        guard entity.domain == "climate",
              entity.attributes.hvac_modes?.contains(mode) == true else { return }
        do {
            try await client().service(domain: "climate", action: "set_hvac_mode",
                                       entityID: entity.id, extra: ["hvac_mode": mode])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setFanMode(_ entity: HAEntity, mode: String) async {
        guard connected && liveConnected && stevoraManifest != nil else { error = "Offline: controls disabled"; return }
        guard entity.domain == "climate",
              entity.attributes.fan_modes?.contains(mode) == true else { return }
        do {
            try await client().service(domain: "climate", action: "set_fan_mode",
                                       entityID: entity.id, extra: ["fan_mode": mode])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setPresetMode(_ entity: HAEntity, mode: String) async {
        guard connected && liveConnected && stevoraManifest != nil else { error = "Offline: controls disabled"; return }
        guard entity.domain == "climate",
              entity.attributes.preset_modes?.contains(mode) == true else { return }
        do {
            try await client().service(domain: "climate", action: "set_preset_mode",
                                       entityID: entity.id, extra: ["preset_mode": mode])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setLightEffect(_ entity: HAEntity, effect: String) async {
        guard connected && liveConnected && stevoraManifest != nil && !entity.id.lowercased().contains("backlight") else { error = "Offline or restricted device"; return }
        guard entity.domain == "light",
              entity.attributes.effect_list?.contains(effect) == true else { return }
        do {
            try await client().service(domain: "light", action: "turn_on",
                                       entityID: entity.id, extra: ["effect": effect])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setBrightness(_ entity: HAEntity, value: Double) async {
        guard connected && liveConnected && stevoraManifest != nil && !entity.id.lowercased().contains("backlight") else { error = "Offline or restricted device"; return }
        guard entity.domain == "light" else { return }
        do {
            try await client().service(domain: "light", action: "turn_on",
                                       entityID: entity.id, extra: ["brightness_pct": Int(value)])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setColor(_ entity: HAEntity, rgb: [Int]) async {
        guard connected && liveConnected && stevoraManifest != nil && !entity.id.lowercased().contains("backlight") else { error = "Offline or restricted device"; return }
        guard entity.domain == "light", rgb.count == 3,
              rgb.allSatisfy({ (0...255).contains($0) }) else { return }
        do {
            try await client().service(domain: "light", action: "turn_on",
                                       entityID: entity.id, extra: ["rgb_color": rgb])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func runRoutine(_ entity: HAEntity) async {
        guard connected && liveConnected && stevoraManifest != nil && !entity.id.lowercased().contains("backlight") else { error = "Offline or restricted routine"; return }
        guard ["scene", "script", "automation"].contains(entity.domain) else { return }
        do {
            let action = entity.domain == "automation" ? "trigger" : "turn_on"
            try await client().service(domain: entity.domain, action: action, entityID: entity.id)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setLocalHTTPAllowed(_ allowed: Bool) {
        allowLocalHTTP = allowed
        UserDefaults.standard.set(allowed, forKey: "stevora.allowLocalHTTP")
    }

    func setLanguage(_ newValue: String) {
        language = newValue
        UserDefaults.standard.set(newValue, forKey: "stevora.language")
    }

    func logout() {
        liveUpdates.stop()
        CredentialStore.delete(key: "access_token")
        CredentialStore.delete(key: "refresh_token")
        UserDefaults.standard.removeObject(forKey: "stevora.oauth.clientID")
        isOAuthSession = false
        token = ""
        connected = false
        liveConnected = false
        connectionMode = "STEVORA OS"
        stevoraManifest = nil
        entities = []
        favorites = []
        error = nil
    }
}
