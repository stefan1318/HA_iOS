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
    "upstream AI policy retained": (root / "AI_POLICY.md").exists(),
    "existing iOS bundle identifier": "com.stevora.companion.ios" in project,
    "keychain credentials": "CredentialStore" in model and "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in network,
    "HTTPS only": 'url.scheme?.lowercased() == "https"' in network,
    "dynamic device discovery": "controllableDomains.contains($0.domain)" in views,
    "no hard-coded developer device IDs": "climate.air_conditioner" not in views and "light.rgb_cct" not in views,
    "no backlight control": 'contains("backlight")' in model and 'contains("backlight")' in views,
    "offline command gate": model.count("connected && liveConnected") >= 8,
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
