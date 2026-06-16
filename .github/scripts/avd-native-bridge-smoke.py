#!/usr/bin/env python3
import json
import subprocess
import sys
import time


OUT = "avd-native-bridge-smoke.json"
APK = "native-bridge-smoke.apk"
PACKAGE = "com.smlc666.nativebridgesmoke"
ACTIVITY = f"{PACKAGE}/.MainActivity"
TAG = "NativeBridgeSmoke"


def adb(*args, timeout=60):
    return subprocess.run(
        ["adb", *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )


def adb_shell(*args, timeout=60):
    proc = adb("shell", *args, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError(proc.stdout.strip() or f"adb shell exited {proc.returncode}")
    return proc.stdout.strip()


def translation_path():
    return adb_shell(
        "sh",
        "-c",
        "for p in "
        "/system/lib64/libndk_translation.so "
        "/system_ext/lib64/libndk_translation.so "
        "/system/system_ext/lib64/libndk_translation.so; "
        "do test -f \"$p\" && echo \"$p\" && exit 0; done; exit 1",
    )


def write_result(result, exit_code):
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, sort_keys=True)
        f.write("\n")
    print(json.dumps(result, indent=2, sort_keys=True))
    return exit_code


def main():
    started = time.monotonic()
    try:
        bridge_property = adb_shell("getprop", "ro.dalvik.vm.native.bridge")
        if not bridge_property or bridge_property == "0":
            raise RuntimeError(f"native bridge disabled: {bridge_property!r}")
        bridge_path = translation_path()

        adb("uninstall", PACKAGE, timeout=30)
        adb("logcat", "-c", timeout=30)

        install = adb("install", "-r", APK, timeout=180)
        if install.returncode != 0:
            raise RuntimeError(f"adb install failed: {install.stdout.strip()}")

        start = adb("shell", "am", "start", "-W", "-n", ACTIVITY, timeout=180)
        if start.returncode != 0:
            raise RuntimeError(f"am start failed: {start.stdout.strip()}")

        time.sleep(5)
        logcat = adb("logcat", "-d", timeout=60)
        log_lines = [
            line for line in logcat.stdout.splitlines()
            if TAG in line or "AndroidRuntime" in line or "linker" in line
        ]
        saw_onload = any("JNI_OnLoad reached" in line for line in log_lines)
        saw_post_load = any("after System.loadLibrary" in line for line in log_lines)
        saw_on_create = any("MainActivity.onCreate" in line for line in log_lines)
        if not (saw_onload and saw_post_load and saw_on_create):
            raise RuntimeError("native-bridge harness did not reach JNI_OnLoad + Activity startup")

        result = {
            "status": "pass",
            "native_bridge_property": bridge_property,
            "translation_library": bridge_path,
            "install_output": install.stdout.strip(),
            "start_output": start.stdout.strip(),
            "matching_log_lines": log_lines[-20:],
            "duration_ms": int((time.monotonic() - started) * 1000),
        }
        return write_result(result, 0)
    except Exception as exc:  # noqa: BLE001 - CI report should capture every smoke failure.
        result = {
            "status": "fail",
            "detail": str(exc),
            "duration_ms": int((time.monotonic() - started) * 1000),
        }
        return write_result(result, 1)


if __name__ == "__main__":
    sys.exit(main())
