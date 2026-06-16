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
    runner_steps = [
        step for step in steps
        if step.get("uses") == "reactivecircus/android-emulator-runner@v2"
    ]
    if len(runner_steps) != 1:
        raise SystemExit(f"expected exactly one emulator runner step, found {len(runner_steps)}")

    script = runner_steps[0]["with"]["script"]
    if script.strip() != "sh .github/scripts/avd-smoke-report.sh":
        raise SystemExit("emulator runner script must be a single helper invocation")
    if "\n" in script.strip():
        raise SystemExit("emulator runner script must not depend on multiline shell semantics")
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
