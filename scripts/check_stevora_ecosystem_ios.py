#!/usr/bin/env python3
"""STEVORA iOS ecosystem static release gate; not a device or security audit."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
def read(path):
    return (root / path).read_text(encoding="utf-8")
contract = read("STEVORA_ECOSYSTEM_CONTRACT.md")
model = read("STEVORA/iOSApp/Sources/StevoraModel.swift")
views = read("STEVORA/iOSApp/Sources/StevoraViews.swift")
network = read("STEVORA/iOSApp/Sources/StevoraNetwork.swift")
live = read("STEVORA/iOSApp/Sources/StevoraLiveUpdates.swift")
assist = read("STEVORA/iOSApp/Sources/StevoraAssistantGateway.swift")
project = read("STEVORA/iOSApp/project.yml")
checks = {
    "iOS ecosystem contract": "[STE-03]" in contract and "[STE-00]" in contract and "[STE-06]" in contract,
    "Ecosystem is OS plus native Android and iOS": "STEVORA Ecosystem = STEVORA OS + STEVORA App for Android + STEVORA App for iOS" in contract,
    "iOS is an OS native client": "native client of STEVORA OS" in contract and "single source of truth" in contract,
    "OS integrated components defined": all(x in contract for x in ("Stevora Core", "Stevora Universal Integration", "Stevora Home Panel 7.1.1", "Stevora Home Hub", "Stevora Frontend", "Stevora People & Presence", "Stevora Manifest")),
    "Hey Stevora OS provider and package rules": all(x in contract for x in ("Hey Stevora is a built-in", "installed", "purchased package")),
    "Memory private owner only excluded from iOS": all(x in contract for x in ("owner\'s homes only", "not bundled", "disabled by default")),
    "upstream AI policy retained": (root / "AI_POLICY.md").exists(),
    "existing iOS bundle identifier": "com.stevora.companion.ios" in project,
    "keychain credentials": "CredentialStore" in model and "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in network,
    "HTTPS default with explicit private LAN HTTP opt-in": all(token in network for token in ['scheme == "https"', 'scheme == "http", allowLocalHTTP', 'values[0] == 10', 'values[0] == 172', 'values[0] == 192']) and "allowLocalHTTP: Bool = false" in network,
    "no global ATS bypass": "NSAllowsArbitraryLoads: NO" in project and "NSAllowsLocalNetworking: YES" in project,
    "local HTTP explicit UI consent": "model.allowLocalHTTP" in views and "model.setLocalHTTPAllowed" in views,
    "WebSocket transport policy": "StevoraTransportPolicy.permits" in live and 'parts.scheme = baseURL.scheme?.lowercased() == "http" ? "ws" : "wss"' in live,
    "Managers and Assist use same LAN transport policy": "StevoraTransportPolicy.permits" in assist and 'parts.scheme = baseURL.scheme?.lowercased() == "http" ? "ws" : "wss"' in assist and "allowLocalHTTP: model.allowLocalHTTP" in read("STEVORA/iOSApp/Sources/StevoraManagersView.swift"),
    "dynamic device discovery": "controllableDomains.contains($0.domain)" in views,
    "no hard-coded developer device IDs": "climate.air_conditioner" not in views and "light.rgb_cct" not in views,
    "no backlight control": 'contains("backlight")' in model and 'contains("backlight")' in views,
    "offline command gate": "guard connected && liveConnected && stevoraManifest != nil" in model and model.count("guard allows(entity,") >= 8 and "manifest.controllable?.contains(entity.id) == true" in model and "device.availableControls?.contains(action) == true" in model,
    "WebSocket ready after subscription": "onReady()" in live and "subscribed = true" in live,
    "role-based Assist routing": "auth/current_user" in assist and "routeChanged" in assist,
    "BG/EN UI": "func localized(" in model and "Български" in views and "English" in views,
    "voice consent documented": "Explicit microphone/speech consent" in contract,
    "manual acceptance documented": "manual security, OAuth, offline" in contract,
}
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
if not all(checks.values()):
    sys.exit("STEVORA iOS ecosystem static gate failed")
print("Static ecosystem contract passed; manual device and security acceptance still required.")
