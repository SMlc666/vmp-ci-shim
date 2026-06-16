#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys
import time


OUT = "avd-native-bridge-smoke.json"
APK = "native-bridge-smoke.apk"
PACKAGE = "com.smlc666.nativebridgesmoke"
ACTIVITY = f"{PACKAGE}/.MainActivity"
TAG = "NativeBridgeSmoke"
BATTTERY_EXCERPT_LIMIT = 40


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


def adb_shell_script(script, timeout=60):
    return adb_shell(script, timeout=timeout)


def translation_path():
    return adb_shell_script(
        "if test -f /system/lib64/libndk_translation.so; then "
        "echo /system/lib64/libndk_translation.so; "
        "elif test -f /system_ext/lib64/libndk_translation.so; then "
        "echo /system_ext/lib64/libndk_translation.so; "
        "elif test -f /system/system_ext/lib64/libndk_translation.so; then "
        "echo /system/system_ext/lib64/libndk_translation.so; "
        "else exit 1; fi",
    )


def write_result(result, exit_code):
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, sort_keys=True)
        f.write("\n")
    print(json.dumps(result, indent=2, sort_keys=True))
    return exit_code


def evaluate_smoke_output(logcat_text, tag, work_dir):
    del work_dir
    log_lines = [
        line for line in logcat_text.splitlines()
        if tag in line or "AndroidRuntime" in line or "linker" in line
    ]
    saw_onload = any("JNI_OnLoad reached" in line for line in log_lines)
    saw_post_load = any("after System.loadLibrary" in line for line in log_lines)
    saw_on_create = any("MainActivity.onCreate" in line for line in log_lines)
    saw_battery_begin = any("cpp_business battery begin" in line for line in log_lines)
    saw_battery_end = any("cpp_business battery end" in line for line in log_lines)
    battery_lines = []
    for line in log_lines:
        if tag not in line:
            continue
        _, _, payload = line.partition(f"{tag}:")
        payload = payload.strip()
        if payload.startswith("PASS:") or payload.startswith("FAIL:") or payload.startswith("BATTERY-FAILS="):
            battery_lines.append(payload)

    saw_battery_zero = any(line == "BATTERY-FAILS=0" for line in battery_lines)
    if not (saw_onload and saw_post_load and saw_on_create and saw_battery_begin and saw_battery_end and saw_battery_zero):
        missing = []
        if not saw_onload:
            missing.append("JNI_OnLoad reached")
        if not saw_post_load:
            missing.append("after System.loadLibrary")
        if not saw_on_create:
            missing.append("MainActivity.onCreate")
        if not saw_battery_begin:
            missing.append("cpp_business battery begin")
        if not saw_battery_end:
            missing.append("cpp_business battery end")
        if not saw_battery_zero:
            missing.append("BATTERY-FAILS=0")
        return {
            "status": "fail",
            "detail": "native-bridge smoke missing required markers: " + ", ".join(missing),
            "matching_log_lines": log_lines[-20:],
            "battery_excerpt": battery_lines[-BATTTERY_EXCERPT_LIMIT:],
        }

    return {
        "status": "pass",
        "matching_log_lines": log_lines[-20:],
        "battery_excerpt": battery_lines[-BATTTERY_EXCERPT_LIMIT:],
        "battery_fails": 0,
    }


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
        parsed = evaluate_smoke_output(logcat.stdout, TAG, pathlib.Path("."))
        if parsed["status"] != "pass":
            raise RuntimeError(parsed["detail"])

        result = {
            "status": "pass",
            "native_bridge_property": bridge_property,
            "translation_library": bridge_path,
            "install_output": install.stdout.strip(),
            "start_output": start.stdout.strip(),
            "matching_log_lines": parsed["matching_log_lines"],
            "battery_excerpt": parsed["battery_excerpt"],
            "battery_fails": parsed["battery_fails"],
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
