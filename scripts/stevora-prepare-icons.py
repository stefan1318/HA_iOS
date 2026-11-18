#!/usr/bin/env python3
"""Generate AppIcon assets from the verified original STEVORA logo for CI."""
import hashlib
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / "STEVORA/iOSApp/Branding/stevora-logo.png"
expected = "58e54712a07d909695a4bbdef5ef0d80dccae05e2485730011b8e588951349e0"
if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
    raise SystemExit("Official STEVORA logo is missing or differs from approved original")

iconsets = root / "Sources/App/Resources/Assets.xcassets"
generated = set()
for iconset in sorted(iconsets.glob("AppIcon*.appiconset")):
    images = json.loads((iconset / "Contents.json").read_text())["images"]
    for entry in images:
        filename = entry.get("filename")
        if not filename:
            continue
        size = entry["size"]
        points = float(size.split("x", 1)[0])
        scale = float(str(entry.get("scale", "1x")).rstrip("x"))
        pixels = round(points * scale)
        output = iconset / filename
        if output in generated:
            continue
        subprocess.run(
            ["sips", "-s", "format", "png", "-z", str(pixels), str(pixels),
             str(source), "--out", str(output)],
            check=True, stdout=subprocess.DEVNULL,
        )
        generated.add(output)
print(f"Generated {len(generated)} official STEVORA AppIcon PNG assets")
