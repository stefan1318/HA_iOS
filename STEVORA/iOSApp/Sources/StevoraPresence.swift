import CoreLocation
import CryptoKit
import SwiftUI
import UIKit

/// Location consent and registration belong to one OS installation and one authenticated account.
@MainActor
final class StevoraPresence: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var enabled = false
    @Published private(set) var background = false
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var ready = false
    @Published private(set) var lastSent: Date?
    @Published private(set) var failed = false

    private let manager = CLLocationManager()
    private var api: HAClient?
    private var scope: String?
    private var delivery: Task<Void, Never>?
    private var pending: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20
        authorization = manager.authorizationStatus
    }

    func bind(_ client: HAClient, installation: String, user: String) {
        let identity = [client.baseURL.absoluteString, installation, user].joined(separator: "\n")
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        if key == scope { api = client; return }
        suspend()
        api = client
        scope = key
        enabled = UserDefaults.standard.bool(forKey: "presence.enabled." + key)
        background = UserDefaults.standard.bool(forKey: "presence.background." + key)
        ready = true
        updateMonitoring()
    }

    func suspend() {
        stop()
        scope = nil
        api = nil
        enabled = false
        background = false
        ready = false
        lastSent = nil
        failed = false
    }

    func setEnabled(_ value: Bool) {
        guard let scope else { return }
        enabled = value
        UserDefaults.standard.set(value, forKey: "presence.enabled." + scope)
        if !value {
            setBackground(false)
            lastSent = nil
            failed = false
        } else if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        updateMonitoring()
    }

    func setBackground(_ value: Bool) {
        guard let scope else { return }
        background = value && enabled
        UserDefaults.standard.set(background, forKey: "presence.background." + scope)
        if background && manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        updateMonitoring()
    }

    private func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        delivery?.cancel()
        delivery = nil
        pending = nil
    }

    private func updateMonitoring() {
        authorization = manager.authorizationStatus
        guard enabled, ready, authorization == .authorizedAlways || authorization == .authorizedWhenInUse else {
            stop()
            return
        }
        let allowBackground = background && authorization == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = allowBackground
        manager.showsBackgroundLocationIndicator = allowBackground
        if allowBackground && CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateMonitoring()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if enabled { failed = true }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let scope, let api, enabled, let fix = locations.last,
              manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse,
              UIApplication.shared.applicationState != .background || (background && manager.authorizationStatus == .authorizedAlways),
              fix.horizontalAccuracy >= 0, abs(fix.timestamp.timeIntervalSinceNow) < 120,
              CLLocationCoordinate2DIsValid(fix.coordinate) else { return }
        pending = fix
        guard delivery == nil else { return }
        delivery = Task {
            defer { if !Task.isCancelled { delivery = nil } }
            do {
                let key = "presence.webhook." + scope
                let webhook: String
                if let saved = CredentialStore.read(key: key) {
                    webhook = saved
                } else {
                    let deviceKey = "presence.device." + scope
                    let deviceID = UserDefaults.standard.string(forKey: deviceKey) ?? UUID().uuidString
                    UserDefaults.standard.set(deviceID, forKey: deviceKey)
                    webhook = try await api.registerPresence(deviceID: deviceID)
                    try Task.checkCancellation()
                    guard CredentialStore.save(webhook, key: key) else { throw HAError.unexpectedResponse }
                }
                while let next = pending {
                    try Task.checkCancellation()
                    pending = nil
                    do {
                        try await api.sendPresence(next, webhook: webhook)
                    } catch HAError.registrationExpired {
                        CredentialStore.delete(key: key)
                        throw HAError.registrationExpired
                    }
                    try Task.checkCancellation()
                    lastSent = Date()
                    failed = false
                }
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    func requestUpdate() {
        guard ready, enabled, authorization == .authorizedAlways || authorization == .authorizedWhenInUse else { return }
        manager.requestLocation()
    }
}
