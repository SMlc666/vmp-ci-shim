#!/usr/bin/env python3
import pathlib

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "avd-smoke.yml"
HELPER = ROOT / ".github" / "scripts" / "avd-smoke-report.sh"
DEVICE_TESTS = ROOT / ".github" / "scripts" / "avd-device-tests.py"


def main() -> None:
    data = yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))
    steps = data["jobs"]["avd_smoke"]["steps"]
    step_names = {step.get("name", ""): step for step in steps}
    if "Enable KVM" not in step_names:
        raise SystemExit("missing Enable KVM step")
    enable_kvm_run = str(step_names["Enable KVM"].get("run", ""))
    if "99-kvm4all.rules" not in enable_kvm_run:
        raise SystemExit("Enable KVM step must install the standard udev rule")

    restore_steps = [step for step in steps if step.get("uses") == "actions/cache/restore@v4"]
    save_steps = [step for step in steps if step.get("uses") == "actions/cache/save@v4"]
    if len(restore_steps) != 1:
        raise SystemExit(f"expected exactly one actions/cache/restore step, found {len(restore_steps)}")
    if len(save_steps) != 1:
        raise SystemExit(f"expected exactly one actions/cache/save step, found {len(save_steps)}")
    cache_step = restore_steps[0]
    if cache_step.get("id") != "avd-cache":
        raise SystemExit("AVD cache step must use id=avd-cache")
    cache_path = str(cache_step.get("with", {}).get("path", ""))
    if "~/.android/avd/*" not in cache_path or "~/.android/adb*" not in cache_path:
        raise SystemExit("AVD cache step must cache ~/.android/avd/* and ~/.android/adb*")
    save_step = save_steps[0]
    if save_step.get("if") != "steps.avd-cache.outputs.cache-hit != 'true'":
        raise SystemExit("AVD cache save step must run only on cache miss")

    runner_steps = [
        step for step in steps
        if step.get("uses") == "reactivecircus/android-emulator-runner@v2"
    ]
    if len(runner_steps) != 2:
        raise SystemExit(f"expected exactly two emulator runner steps, found {len(runner_steps)}")

    snapshot_steps = [step for step in runner_steps if step.get("with", {}).get("script") == 'echo "Generated AVD snapshot for caching."']
    if len(snapshot_steps) != 1:
        raise SystemExit("missing snapshot-generation emulator step")
    snapshot_step = snapshot_steps[0]
    if snapshot_step.get("if") != "steps.avd-cache.outputs.cache-hit != 'true'":
        raise SystemExit("snapshot-generation step must run only on cache miss")
    if snapshot_step.get("with", {}).get("force-avd-creation") is not False:
        raise SystemExit("snapshot-generation step must set force-avd-creation=false")
    snapshot_options = str(snapshot_step.get("with", {}).get("emulator-options", ""))
    if "-no-snapshot" in snapshot_options:
        raise SystemExit("snapshot-generation step must not disable snapshots")

    test_steps = [step for step in runner_steps if step.get("with", {}).get("script") == "sh .github/scripts/avd-smoke-report.sh"]
    if len(test_steps) != 1:
        raise SystemExit("missing test emulator step")
    test_step = test_steps[0]
    script = test_step["with"]["script"]
    if "\n" in script.strip():
        raise SystemExit("emulator runner test script must not depend on multiline shell semantics")
    if test_step.get("with", {}).get("force-avd-creation") is not False:
        raise SystemExit("test emulator step must set force-avd-creation=false")
    test_options = str(test_step.get("with", {}).get("emulator-options", ""))
    if "-no-snapshot-save" not in test_options:
        raise SystemExit("test emulator step must disable snapshot saving")
    if not HELPER.is_file():
        raise SystemExit(f"missing helper script: {HELPER.relative_to(ROOT)}")
    helper_text = HELPER.read_text(encoding="utf-8")
    if "python3 .github/scripts/avd-device-tests.py" not in helper_text:
        raise SystemExit("AVD smoke helper must run device tests")
    if not DEVICE_TESTS.is_file():
        raise SystemExit(f"missing device test script: {DEVICE_TESTS.relative_to(ROOT)}")
    upload_steps = [
        step for step in steps
        if step.get("uses") == "actions/upload-artifact@v4"
    ]
    artifact_paths = "\n".join(str(step.get("with", {}).get("path", "")) for step in upload_steps)
    if "avd-device-tests.json" not in artifact_paths:
        raise SystemExit("AVD smoke artifacts must include avd-device-tests.json")

    print("avd smoke workflow ok")


if __name__ == "__main__":
    main()
