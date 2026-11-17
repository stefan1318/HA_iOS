import Foundation
import SwiftUI

@MainActor
final class StevoraModel: ObservableObject {
    private let liveUpdates = StevoraLiveUpdates()
    @Published var address = UserDefaults.standard.string(forKey: "stevora.address") ?? ""
    @Published var token = ""
    @Published var connected = false
    @Published var busy = false
    @Published var error: String?
    @Published var entities: [HAEntity] = []
    @Published var language: String = UserDefaults.standard.string(forKey: "stevora.language") ?? "bg"

    init() {
        if let saved = CredentialStore.read(key: "access_token"), !address.isEmpty {
            token = saved
            Task { await connect(persist: false) }
        }
    }

    func localized(_ bg: String, _ en: String) -> String { language == "bg" ? bg : en }

    private func client() throws -> HAClient {
        try HAClient(address: address, token: token)
    }

    func connect(persist: Bool = true) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let api = try client()
            try await api.check()
            let loaded = try await api.states()
            if persist && !CredentialStore.save(token, key: "access_token") {
                throw NSError(domain: "STEVORA", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not securely store access token"])
            }
            UserDefaults.standard.set(address, forKey: "stevora.address")
            entities = loaded
            connected = true
            liveUpdates.start(address: address, token: token, onChange: { [weak self] entity in
                guard let self, self.connected else { return }
                if let index = self.entities.firstIndex(where: { $0.id == entity.id }) {
                    self.entities[index] = entity
                } else {
                    self.entities.append(entity)
                }
            }, onReconnect: { [weak self] in
                await self?.refresh()
            })
        } catch {
            liveUpdates.stop()
            connected = false
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
        token = ""
        connected = false
        entities = []
        error = nil
    }
}
