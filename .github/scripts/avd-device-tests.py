#!/usr/bin/env python3
import json
import subprocess
import sys
import time


OUT = "avd-device-tests.json"


def adb(*args, timeout=30):
    return subprocess.run(
        ["adb", *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )


def adb_shell(*args, timeout=30):
    proc = adb("shell", *args, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError(proc.stdout.strip() or f"adb shell exited {proc.returncode}")
    return proc.stdout.strip()


def run_case(name, fn):
    started = time.monotonic()
    try:
        detail = fn()
        status = "pass"
    except Exception as exc:  # noqa: BLE001 - CI report should capture every case failure.
        detail = str(exc)
        status = "fail"
    return {
        "name": name,
        "status": status,
        "detail": detail,
        "duration_ms": int((time.monotonic() - started) * 1000),
    }


def case_adb_state():
    proc = adb("get-state", timeout=10)
    state = proc.stdout.strip()
    if proc.returncode != 0 or state != "device":
        raise RuntimeError(state or proc.stdout.strip() or f"adb get-state exited {proc.returncode}")
    return state


def case_sdk_property():
    sdk = adb_shell("getprop", "ro.build.version.sdk")
    if not sdk.isdigit():
        raise RuntimeError(f"unexpected sdk property: {sdk!r}")
    return sdk


def case_abi_property():
    abi = adb_shell("getprop", "ro.product.cpu.abi")
    if not abi:
        raise RuntimeError("empty ro.product.cpu.abi")
    return abi


def case_tmp_write_read():
    path = "/data/local/tmp/vmp-avd-smoke.txt"
    adb_shell("touch", path)
    adb_shell("sh", "-c", f"test -e {path} && echo roundtrip-ok")
    adb_shell("rm", "-f", path)
    return "roundtrip-ok"


def case_device_shell_script():
    actual = adb_shell(
        "sh",
        "-c",
        "echo '#!/system/bin/sh' > /data/local/tmp/vmp-avd-device-test.sh "
        "&& echo 'echo avd-device-test' >> /data/local/tmp/vmp-avd-device-test.sh "
        "&& sh /data/local/tmp/vmp-avd-device-test.sh "
        "&& rm /data/local/tmp/vmp-avd-device-test.sh",
    )
    if actual != "avd-device-test":
        raise RuntimeError(f"script output mismatch: {actual!r}")
    return actual


def main():
    cases = [
        run_case("adb_state_is_device", case_adb_state),
        run_case("sdk_property_is_readable", case_sdk_property),
        run_case("abi_property_is_readable", case_abi_property),
        run_case("data_local_tmp_roundtrip", case_tmp_write_read),
        run_case("device_shell_script_runs", case_device_shell_script),
    ]
    failed = [case for case in cases if case["status"] != "pass"]
    result = {
        "status": "fail" if failed else "pass",
        "failed": len(failed),
        "passed": len(cases) - len(failed),
        "cases": cases,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, sort_keys=True)
        f.write("\n")
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
