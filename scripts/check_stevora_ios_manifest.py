#!/usr/bin/env python3
"""Static regression guard for native STEVORA versioned manifest discovery."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
sources = root / "STEVORA/iOSApp/Sources"
model = (sources / "StevoraModel.swift").read_text()
live = (sources / "StevoraLiveUpdates.swift").read_text()
manifest = (sources / "StevoraManifest.swift").read_text()
views = (sources / "StevoraViews.swift").read_text()
checks = {
    "OS v1 discovery after authenticated subscription": 'subscribed = true' in live and 'type": "stevora/os/v1/manifest"' in live,
    "unsupported manifest disables controls": "onManifest(nil)" in live and 'connected && liveConnected && stevoraManifest != nil' in model,
    "manifest schema and installation validation": 'manifest.schemaVersion == "1.0"' in model and "!manifest.installationId.isEmpty" in model,
    "serialized refresh of opaque manifest fingerprints": "previous.revision > manifest.revision" not in model and "id == requestID, fetchingManifest" in live,
    "no hardcoded Home Hub installation": 'installation_id' in manifest and 'stevoraManifest' in model,
    "manifest-owned room projection": "projectedRooms" in model and "projectedEntities(in roomID:" in model,
    "manifest-owned device visibility": "model.projectedEntities.filter" in views and "model.projectedRooms.map" in views,
    "no silent HA expansion after manifest": "guard let manifest = stevoraManifest else { return [] }" in model and "allowed.contains($0.id)" in model,
    "offline safety intact": "guard connected && liveConnected && stevoraManifest != nil" in model and model.count("guard allows(entity,") >= 8 and "manifest.permits(action, entityID: entity.id)" in model and "controllable?.contains(entityID) == true" in manifest,
    "backlight policy intact": 'contains("backlight")' in model and 'contains("backlight")' in views,
}
for description, passed in checks.items():
    print(("PASS" if passed else "FAIL") + ": " + description)
if not all(checks.values()):
    raise SystemExit(1)

# Run the production decoder and permission checks on the Apple build runner.
import shutil
import subprocess
import tempfile

if compiler := shutil.which("swiftc"):
    with tempfile.TemporaryDirectory() as directory:
        binary = Path(directory) / "dev4-manifest-test"
        subprocess.run([compiler, sources / "StevoraManifest.swift",
                        root / "STEVORA/ContractTests/Dev4ManifestTest.swift", "-o", binary], check=True)
        subprocess.run([binary], check=True)
else:
    print("SKIP: Swift compiler unavailable for the runtime fixture")
