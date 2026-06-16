#!/bin/sh
set -eu

adb wait-for-device

trap 'adb logcat -d > avd-logcat.txt 2>/dev/null || true' EXIT

test_rc=0
python3 .github/scripts/avd-device-tests.py || test_rc=$?

bridge_rc=0
if sh .github/scripts/build-native-bridge-harness.sh; then
  python3 .github/scripts/avd-native-bridge-smoke.py || bridge_rc=$?
else
  bridge_rc=$?
  python3 - <<'PY'
import json

result = {
    "status": "fail",
    "detail": "native-bridge harness build failed",
}
with open("avd-native-bridge-smoke.json", "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2, sort_keys=True)
    f.write("\n")
print(json.dumps(result, indent=2, sort_keys=True))
PY
fi
if [ "$bridge_rc" -ne 0 ]; then
  test_rc=1
fi

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


try:
    with open("avd-device-tests.json", encoding="utf-8") as f:
        tests = json.load(f)
except FileNotFoundError:
    tests = {
        "status": "fail",
        "failed": 1,
        "passed": 0,
        "cases": [
            {
                "name": "avd_device_tests_json_present",
                "status": "fail",
                "detail": "avd-device-tests.json was not produced",
                "duration_ms": 0,
            }
        ],
    }

try:
    with open("avd-project-probe.json", encoding="utf-8") as f:
        project_probe = json.load(f)
except FileNotFoundError:
    project_probe = {
        "status": "missing",
        "summary": "avd-project-probe.json was not produced",
        "signals": {},
    }

try:
    with open("avd-native-bridge-smoke.json", encoding="utf-8") as f:
        native_bridge_smoke = json.load(f)
except FileNotFoundError:
    native_bridge_smoke = {
        "status": "missing",
        "detail": "avd-native-bridge-smoke.json was not produced",
    }


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
        "linker64": adb_shell("test -x /system/bin/linker64 && echo present || echo missing"),
    },
    "scope": {
        "mode": "manual_non_blocking" if os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch" else "nightly_auxiliary_gate",
        "does_not_validate_general_arm64_vmp_compatibility": True,
        "does_not_replace_bionic_shim_gate": True,
        "purpose": "Verify x86_64 AVD boot, native-bridge/libndk availability, adb control, and a translated cpp_business arm64 Android smoke that ends with BATTERY-FAILS=0.",
    },
    "project_probe": project_probe,
    "native_bridge_smoke": native_bridge_smoke,
    "tests": tests,
}

with open("avd-smoke-report.json", "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, sort_keys=True)
    f.write("\n")
print(json.dumps(report, indent=2, sort_keys=True))
PY

exit "$test_rc"
