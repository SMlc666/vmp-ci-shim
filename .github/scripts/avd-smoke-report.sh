#!/bin/sh
set -eu

adb wait-for-device

trap 'adb logcat -d > avd-logcat.txt 2>/dev/null || true' EXIT

python3 - <<'PY'
import json
import os
import subprocess


def adb_shell(*args):
    try:
        return subprocess.check_output(
            ["adb", "shell", *args],
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        ).strip()
    except subprocess.CalledProcessError as exc:
        return "ERROR: " + (exc.output or "").strip()
    except subprocess.TimeoutExpired:
        return "ERROR: timeout"


report = {
    "workflow": "avd-smoke",
    "event_name": os.environ.get("GITHUB_EVENT_NAME", ""),
    "target_ref": os.environ.get("TARGET_REF", ""),
    "private_sha": os.environ.get("PRIVATE_SHA", ""),
    "runner_os": os.environ.get("RUNNER_OS", ""),
    "avd": {
        "api_level": adb_shell("getprop", "ro.build.version.sdk"),
        "release": adb_shell("getprop", "ro.build.version.release"),
        "cpu_abi": adb_shell("getprop", "ro.product.cpu.abi"),
        "cpu_abilist": adb_shell("getprop", "ro.product.cpu.abilist"),
        "model": adb_shell("getprop", "ro.product.model"),
        "linker64": adb_shell("sh", "-c", "test -x /system/bin/linker64 && echo present || echo missing"),
    },
    "scope": {
        "mode": "manual_non_blocking" if os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch" else "nightly_auxiliary_gate",
        "does_not_validate_arm64_vmp": True,
        "does_not_replace_bionic_shim_gate": True,
        "purpose": "Verify AVD boot, adb control, and Android runtime smoke reporting.",
    },
}

with open("avd-smoke-report.json", "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, sort_keys=True)
    f.write("\n")
print(json.dumps(report, indent=2, sort_keys=True))
PY
