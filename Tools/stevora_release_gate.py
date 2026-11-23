#!/usr/bin/env python3
"""Fail closed on STEVORA iOS release identity; never claim device tests ran."""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=pathlib.Path)
    args = parser.parse_args()
    errors = []
    config = ROOT / "Configuration/HomeAssistant.xcconfig"
    if not config.exists():
        errors.append("Missing iOS xcconfig")
        source = ""
    else:
        source = config.read_text(encoding="utf-8")
    bundle = re.search(r"^BUNDLE_ID_PREFIX\s*=\s*(\S+)", source, re.M)
    if not bundle or not bundle.group(1).startswith("com.stevora"):
        errors.append("STEVORA bundle prefix not configured (upstream identity must not ship)")
    if not any("stevora" in p.name.lower() for p in (ROOT / "Sources").rglob("*") if p.is_file()):
        errors.append("No STEVORA-branded source files found")
    localization_files = list((ROOT / "Sources").rglob("*.strings"))
    if not localization_files:
        errors.append("No .strings localization files found")
    else:
        languages = {part.lower() for path in localization_files for part in path.parts if part.endswith(".lproj")}
        if not {"en.lproj", "bg.lproj"}.issubset(languages):
            errors.append("Both BG and EN .lproj translations are required for release")
    text = "## STEVORA iOS release gate\n\n" + (
        "\n".join("- FAIL: " + error for error in errors) if errors else
        "- PASS: static product identity and localization prerequisites\n"
        "- NOTE: login, manifest, HTTP/HTTPS, room/device permissions and real-device "
        "installation still require integration/device testing"
    ) + "\n"
    print(text)
    if args.report:
        args.report.write_text(text, encoding="utf-8")
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
