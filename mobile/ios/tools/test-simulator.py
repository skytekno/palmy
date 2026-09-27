#!/usr/bin/env python3
"""Select an installed iPhone runtime and execute the checked-in SwiftUI lifecycle suite."""
import json
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))
devices = [device for runtime, group in inventory["devices"].items() if "iOS" in runtime for device in group if device["name"].startswith("iPhone") and device.get("isAvailable", True)]
requested = os.environ.get("PALMY_SIMULATOR_ID")
if requested:
    devices = [device for device in devices if device["udid"] == requested]
if not devices:
    raise SystemExit("No available iPhone simulator. Install an iOS runtime in Xcode before running this gate.")
devices.sort(key=lambda device: (device["state"] != "Booted", device["name"], device["udid"]))
device = devices[0]
print(f"Using {device['name']} ({device['udid']})", flush=True)
result = subprocess.run([
    "xcodebuild", "-project", "Palmy.xcodeproj", "-scheme", "Palmy", "-configuration", "Debug",
    "-destination", f"platform=iOS Simulator,id={device['udid']}", "-derivedDataPath", "DerivedData",
    "-parallel-testing-enabled", "NO", "CODE_SIGNING_ALLOWED=NO",
    f"PALMY_UI_LIVE_API={os.environ.get('PALMY_UI_LIVE_API', '0')}", "test",
], cwd=root)
raise SystemExit(result.returncode)
