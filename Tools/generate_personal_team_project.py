#!/usr/bin/env python3
"""Generate the local, iPhone-only STEVORA development project."""

import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "HomeAssistant.xcodeproj"
DESTINATION = ROOT / "STEVORA-Personal.xcodeproj"
CONFIGURATION = "Debug-Personal"
SCHEME = "STEVORA-Personal"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle_prefix", help="A unique reverse-DNS prefix, e.g. com.yourname.stevora.a1b2c3")
    args = parser.parse_args()
    prefix = args.bundle_prefix
    if not re.fullmatch(r"[a-z][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*){2,}", prefix) or len(prefix) > 120:
        parser.error("use a lowercase reverse-DNS prefix with at least three components")
    if DESTINATION.exists():
        parser.error(f"{DESTINATION.name} already exists; keep or rename it before regenerating")

    project = json.loads(subprocess.check_output([
        "/usr/bin/plutil", "-convert", "json", "-o", "-", str(SOURCE / "project.pbxproj"),
    ]))
    objects = project["objects"]
    root = objects[project["rootObject"]]
    targets = {
        objects[target]["name"]: target
        for target in root["targets"]
        if objects[target]["name"] in {"App", "Shared-iOS", "Codegen"}
    }
    if targets.keys() != {"App", "Shared-iOS", "Codegen"}:
        parser.error("expected App, Shared-iOS and Codegen targets")
    root["targets"] = list(targets.values())
    attributes = root["attributes"]["TargetAttributes"]
    root["attributes"]["TargetAttributes"] = {
        target: {key: value for key, value in attributes.get(target, {}).items()
                 if key not in {"SystemCapabilities", "DevelopmentTeam"}}
        for target in root["targets"]
    }

    for target in targets.values():
        obj = objects[target]
        obj["dependencies"] = [
            dep for dep in obj["dependencies"] if objects[dep].get("target") in root["targets"]
        ]
        obj["buildPhases"] = [
            phase for phase in obj["buildPhases"]
            if (objects[phase]["isa"] != "PBXCopyFilesBuildPhase"
                or objects[phase].get("name") == "Embed Frameworks")
            and objects[phase].get("name") not in {
                "Enable Special Entitlements", "Run SwiftLint", "Swiftlint",
            }
        ]

    def debug_settings(owner):
        configurations = objects[owner["buildConfigurationList"]]
        debug, = [
            reference for reference in configurations["buildConfigurations"]
            if objects[reference]["name"] == "Debug"
        ]
        configurations["buildConfigurations"] = [debug]
        configurations["defaultConfigurationName"] = CONFIGURATION
        objects[debug]["name"] = CONFIGURATION
        return objects[debug]["buildSettings"]

    settings = debug_settings(root)
    settings.update({
        "BUNDLE_ID_PREFIX": prefix,
        "DEVELOPMENT_TEAM": "",
        "CODE_SIGN_STYLE": "Automatic",
        "CODE_SIGN_STYLE[sdk=iphoneos*]": "Automatic",
        "PROVISIONING_PROFILE_SPECIFIER": "",
        "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": "",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG STEVORA_PERSONAL_TEAM",
    })
    for name, target in targets.items():
        build_settings = debug_settings(objects[target])
        for key in list(build_settings):
            if key.startswith(("CODE_SIGN_ENTITLEMENTS", "DEVELOPMENT_TEAM", "PROVISIONING_PROFILE")):
                del build_settings[key]
        build_settings["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
        build_settings["SUPPORTS_MACCATALYST"] = "NO"
        if name == "App":
            build_settings.update({
                "CODE_SIGN_ENTITLEMENTS": "",
                "INFOPLIST_FILE": f"{DESTINATION.name}/App-Info.plist",
                "PRODUCT_NAME": "STEVORA Personal",
                "TARGETED_DEVICE_FAMILY": "1",
            })

    info = plistlib.loads((ROOT / "Sources/App/Resources/Info.plist").read_bytes())
    info["UIBackgroundModes"].remove("remote-notification")
    info["CFBundleDisplayName"] = "STEVORA Personal"

    scheme = ET.parse(SOURCE / "xcshareddata/xcschemes/App-Debug.xcscheme")
    for action in scheme.getroot():
        if "buildConfiguration" in action.attrib:
            action.set("buildConfiguration", CONFIGURATION)
    for reference in scheme.iter("BuildableReference"):
        reference.set("ReferencedContainer", f"container:{DESTINATION.name}")
        if reference.get("BlueprintName") == "App":
            reference.set("BuildableName", "STEVORA Personal.app")
    test_action = scheme.getroot().find("TestAction")
    test_action.clear()
    test_action.set("buildConfiguration", CONFIGURATION)
    for entry in scheme.iter("BuildActionEntry"):
        entry.set("buildForTesting", "NO")
        entry.set("buildForArchiving", "NO")
    for launch_arguments in scheme.iter("CommandLineArguments"):
        for argument in launch_arguments:
            argument.set("isEnabled", "NO")

    DESTINATION.mkdir()
    try:
        shutil.copytree(SOURCE / "project.xcworkspace", DESTINATION / "project.xcworkspace",
                        ignore=shutil.ignore_patterns("xcuserdata"))
        workspace = DESTINATION / "project.xcworkspace/contents.xcworkspacedata"
        workspace.write_text(workspace.read_text().replace(
            f"self:{SOURCE.name}", f"self:{DESTINATION.name}",
        ))
        (DESTINATION / "project.pbxproj").write_bytes(plistlib.dumps(project, sort_keys=False))
        (DESTINATION / "App-Info.plist").write_bytes(plistlib.dumps(info, sort_keys=False))
        schemes = DESTINATION / "xcshareddata/xcschemes"
        schemes.mkdir(parents=True)
        scheme.write(schemes / f"{SCHEME}.xcscheme", encoding="UTF-8", xml_declaration=True)
    except Exception:
        shutil.rmtree(DESTINATION)
        raise
    print(f"Open {DESTINATION.name}; select {SCHEME} and choose your Personal Team for App.")
    print(f"App bundle identifier: {prefix}.HomeAssistant.dev")


if __name__ == "__main__":
    main()
