#!/usr/bin/env python3
"""Static regression guard for native STEVORA optional manifest discovery."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
sources = root / "STEVORA/iOSApp/Sources"
model = (sources / "StevoraModel.swift").read_text()
live = (sources / "StevoraLiveUpdates.swift").read_text()
manifest = (sources / "StevoraManifest.swift").read_text()
views = (sources / "StevoraViews.swift").read_text()
checks = {
    "optional discovery after authenticated subscription": 'subscribed = true' in live and 'type": "stevora/manifest"' in live,
    "native HA fallback on unsupported result": "onManifest(nil)" in live and 'connectionMode = "Home Assistant"' in model,
    "manifest schema and installation validation": 'manifest.schemaVersion == "1.0"' in model and "!manifest.installationId.isEmpty" in model,
    "manifest revision monotonicity": "previous.revision > manifest.revision" in model,
    "no hardcoded Home Hub installation": 'installation_id' in manifest and 'stevoraManifest' in model,
    "offline safety intact": model.count("connected && liveConnected") >= 8,
    "backlight policy intact": 'contains("backlight")' in model and 'contains("backlight")' in views,
}
for description, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + description)
if not all(checks.values()):
    raise SystemExit(1)
