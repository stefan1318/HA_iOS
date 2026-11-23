import Foundation
import SwiftUI
import CryptoKit
import AuthenticationServices

@MainActor
final class StevoraModel: ObservableObject {
    private let liveUpdates = StevoraLiveUpdates()
    let presence = StevoraPresence()
    @Published private(set) var accountName: String?
    @Published private(set) var isAdmin = false
    private var userID: String?
    private var session = UUID()
    @Published private(set) var savingLanguage = false
    private let oauth = StevoraOAuth()
    @Published var isOAuthSession = false
    @Published var selectedRoom = "all"
    @Published var favorites: Set<String> = []
    @Published var address = UserDefaults.standard.string(forKey: "stevora.address") ?? "" {
        didSet {
            if address != oldValue { token = ""; session = UUID() }
        }
    }
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
            guard url == (try client()).baseURL else { throw HAError.invalidURL }
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

    private var legacyFavoriteKey: String {
        let host = (URL(string: address)?.host ?? address).lowercased()
        let fingerprint = SHA256.hash(data: Data(token.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return "stevora.favorites.\(host).\(fingerprint)"
    }
    private var favoriteKey: String? {
        guard let installation = stevoraManifest?.installationId, let userID else { return nil }
        let scope = [address, installation, userID].joined(separator: "\n")
        let hash = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return "stevora.favorites.v2." + hash
    }

    func toggleFavorite(_ id: String) {
        guard let favoriteKey, projectedEntities.contains(where: { $0.id == id }) else { return }
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: favoriteKey)
    }

    func connect(persist: Bool = true) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let attempt = session
            var api = try client()
            do {
                try await api.check()
            } catch HAError.unauthorized {
                guard !persist, UserDefaults.standard.string(forKey: "stevora.address") == address,
                      let refresh = CredentialStore.read(key: "refresh_token") else { throw HAError.unauthorized }
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
            guard attempt == session else { return }
            if persist && !CredentialStore.save(token, key: "access_token") {
                throw NSError(domain: "STEVORA", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not securely store access token"])
            }
            if persist {
                CredentialStore.delete(key: "refresh_token")
                isOAuthSession = false
            }
            UserDefaults.standard.set(address, forKey: "stevora.address")
            entities = loaded
            favorites = []
            connected = true
            connectionMode = "STEVORA OS"
            stevoraManifest = nil
            liveConnected = false
            startLiveUpdates()
        } catch {
            liveUpdates.stop()
            clearIdentity()
            connected = false
            liveConnected = false
            connectionMode = "STEVORA OS"
            stevoraManifest = nil
            self.error = error.localizedDescription
        }
    }

    private func startLiveUpdates() {
        liveUpdates.start(address: address, token: token, language: language, allowLocalHTTP: allowLocalHTTP, onChange: { [weak self] entity in
            guard let self, self.connected else { return }
            self.liveConnected = true
            if let index = self.entities.firstIndex(where: { $0.id == entity.id }) {
                self.entities[index] = entity
            } else {
                self.entities.append(entity)
            }
        }, onRemove: { [weak self] id in
            self?.entities.removeAll { $0.id == id }
        }, onReady: { [weak self] in
            self?.liveConnected = true
            Task { await self?.refresh() }
        }, onUser: { [weak self] user in
            guard let self, self.connected else { return }
            self.userID = user["id"] as? String
            self.accountName = user["name"] as? String
            self.isAdmin = user["is_admin"] as? Bool == true || user["is_owner"] as? Bool == true
            self.bindPresence()
        }, onLanguage: { [weak self] language in
            self?.language = language
        }, onReconnect: { [weak self] in
            self?.liveConnected = false
            self?.connectionMode = "STEVORA OS"
            self?.stevoraManifest = nil
            self?.clearIdentity()
        }, onAuthExpired: { [weak self] in
            guard let self else { return }
            self.liveConnected = false
            self.stevoraManifest = nil
            self.clearIdentity()
            await self.connect(persist: false)
        }, onManifest: { [weak self] manifest in
            self?.receiveManifest(manifest)
        })
    }

    private func bindPresence() {
        guard liveConnected, let manifest = stevoraManifest, let userID, !userID.isEmpty, let api = try? client() else {
            presence.suspend()
            return
        }
        if let favoriteKey {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: favoriteKey) == nil, let saved = defaults.stringArray(forKey: legacyFavoriteKey) {
                defaults.set(saved, forKey: favoriteKey)
            }
            favorites = Set(defaults.stringArray(forKey: favoriteKey) ?? [])
        }
        presence.bind(api, installation: manifest.installationId, user: userID)
    }

    private func clearIdentity() {
        userID = nil
        accountName = nil
        isAdmin = false
        presence.suspend()
    }

    func displayName(_ entity: HAEntity) -> String {
        stevoraManifest?.entities?.first { $0.entityId == entity.id }?.name ?? entity.name
    }

    func allows(_ entity: HAEntity, _ action: String) -> Bool {
        guard connected && liveConnected && stevoraManifest != nil,
              let manifest = stevoraManifest, let state = entities.first(where: { $0.id == entity.id }),
              !["unknown", "unavailable"].contains(state.state),
              !state.id.lowercased().contains("backlight") else { return false }
        return manifest.permits(action, entityID: entity.id)
    }

    func receiveManifest(_ manifest: StevoraManifest?) {
        guard let manifest, manifest.schemaVersion == "1.0", !manifest.installationId.isEmpty else {
            stevoraManifest = nil
            presence.suspend()
            connectionMode = localized("Липсва съвместим STEVORA OS манифест", "Compatible STEVORA OS manifest unavailable")
            return
        }
        // Revisions are CRC fingerprints. Socket requests are serialized in arrival order.
        stevoraManifest = manifest
        connectionMode = "STEVORA Ecosystem"
        bindPresence()
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
        let attempt = session
        do {
            let snapshot = try await client().states()
            guard connected, attempt == session else { return }
            entities = snapshot
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }

    func toggle(_ entity: HAEntity) async {
        guard allows(entity, "toggle") else { return }
        guard ["light", "switch", "fan"].contains(entity.domain) else { return }
        do {
            try await client().service(domain: entity.domain,
                                       action: entity.state == "on" ? "turn_off" : "turn_on",
                                       entityID: entity.id)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setTemperature(_ entity: HAEntity, value: Double) async {
        guard allows(entity, "temperature") else { return }
        guard entity.domain == "climate" else { return }
        do {
            try await client().service(domain: "climate", action: "set_temperature",
                                       entityID: entity.id, extra: ["temperature": value])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setClimateMode(_ entity: HAEntity, mode: String) async {
        guard allows(entity, "hvac_mode") else { return }
        guard entity.domain == "climate",
              entity.attributes.hvac_modes?.contains(mode) == true else { return }
        do {
            try await client().service(domain: "climate", action: "set_hvac_mode",
                                       entityID: entity.id, extra: ["hvac_mode": mode])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setFanMode(_ entity: HAEntity, mode: String) async {
        guard allows(entity, "fan_mode") else { return }
        guard entity.domain == "climate",
              entity.attributes.fan_modes?.contains(mode) == true else { return }
        do {
            try await client().service(domain: "climate", action: "set_fan_mode",
                                       entityID: entity.id, extra: ["fan_mode": mode])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setPresetMode(_ entity: HAEntity, mode: String) async {
        guard allows(entity, "preset_mode") else { return }
        guard entity.domain == "climate",
              entity.attributes.preset_modes?.contains(mode) == true else { return }
        do {
            try await client().service(domain: "climate", action: "set_preset_mode",
                                       entityID: entity.id, extra: ["preset_mode": mode])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setLightEffect(_ entity: HAEntity, effect: String) async {
        guard allows(entity, "effect") else { return }
        guard entity.domain == "light",
              entity.attributes.effect_list?.contains(effect) == true else { return }
        do {
            try await client().service(domain: "light", action: "turn_on",
                                       entityID: entity.id, extra: ["effect": effect])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setBrightness(_ entity: HAEntity, value: Double) async {
        guard allows(entity, "brightness") else { return }
        guard entity.domain == "light" else { return }
        do {
            try await client().service(domain: "light", action: "turn_on",
                                       entityID: entity.id, extra: ["brightness_pct": Int(value)])
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setColor(_ entity: HAEntity, rgb: [Int]) async {
        guard allows(entity, "color") else { return }
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
        guard stevoraManifest?.controllable?.contains(entity.id) == true, projectedEntities.contains(where: { $0.id == entity.id }),
              !["unknown", "unavailable"].contains(entity.state), ["scene", "script", "automation"].contains(entity.domain) else { return }
        do {
            let action = entity.domain == "automation" ? "trigger" : "turn_on"
            try await client().service(domain: entity.domain, action: action, entityID: entity.id)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func setDetailValue(_ entity: HAEntity, action: String, field: String, value: Any) async {
        guard allows(entity, action) else { return }
        let service: String
        switch (entity.domain, action, field) {
        case ("light", "color_temp", "color_temp_kelvin"): service = "turn_on"
        case ("cover", "position", "position"): service = "set_cover_position"
        case ("cover", "tilt", "tilt_position"): service = "set_cover_tilt_position"
        case ("fan", "percentage", "percentage"): service = "set_percentage"
        case ("fan", "direction", "direction"): service = "set_direction"
        case ("fan", "oscillate", "oscillating"): service = "oscillate"
        case ("fan", "preset_mode", "preset_mode"): service = "set_preset_mode"
        case ("climate", "swing_mode", "swing_mode"): service = "set_swing_mode"
        case ("media_player", "source", "source"): service = "select_source"
        default: return
        }
        do { try await client().service(domain: entity.domain, action: service, entityID: entity.id, extra: [field: value]) }
        catch { self.error = error.localizedDescription }
    }

    func mediaOrCover(_ entity: HAEntity, action: String, volume: Double? = nil) async {
        guard allows(entity, action) else { return }
        let service: String
        var fields: [String: Any] = [:]
        switch (entity.domain, action) {
        case ("cover", "open"), ("cover", "close"), ("cover", "stop"): service = action + "_cover"
        case ("media_player", "play_pause"): service = "media_play_pause"
        case ("media_player", "volume"):
            guard let volume, (0...1).contains(volume) else { return }
            service = "volume_set"
            fields["volume_level"] = volume
        default: return
        }
        do { try await client().service(domain: entity.domain, action: service, entityID: entity.id, extra: fields) }
        catch { self.error = error.localizedDescription }
    }

    func setLocalHTTPAllowed(_ allowed: Bool) {
        allowLocalHTTP = allowed
        UserDefaults.standard.set(allowed, forKey: "stevora.allowLocalHTTP")
    }

    func setLanguage(_ value: String) async {
        guard value != language, ["bg", "en"].contains(value), !savingLanguage, liveConnected else { return }
        let attempt = session
        savingLanguage = true
        defer { savingLanguage = false }
        do {
            let gateway = StevoraAssistantGateway(address: address, token: token, allowLocalHTTP: allowLocalHTTP)
            let key = ["key": "stevora_profile"]
            let existing = try await gateway.adminRequest("frontend/get_user_data", fields: key)
            var profile = existing["value"] as? [String: Any] ?? [:]
            profile["language"] = value
            guard session == attempt, connected else { return }
            _ = try await gateway.adminRequest("frontend/set_user_data", fields: ["key": "stevora_profile", "value": profile])
            guard session == attempt, connected else { return }
            language = value
            UserDefaults.standard.set(value, forKey: "stevora.language")
            liveConnected = false
            stevoraManifest = nil
            startLiveUpdates()
        } catch {
            if session == attempt { self.error = localized("Езикът не бе запазен в дома.", "Could not save the home profile language.") }
        }
    }

    func logout() {
        session = UUID()
        clearIdentity()
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
