# AVD Native-Bridge Smoke Design

Date: 2026-06-16
Status: Approved for implementation
Scope: Keep the standalone Android Emulator lane, but make it validate the x86_64 KVM guest plus the image-provided native-bridge/libndk translation path.

## Goal

Add an Android Emulator auxiliary signal with two operating modes:

- Manual `workflow_dispatch`: non-blocking smoke. Failures are reported in artifacts but do not replace or weaken the existing `CI` workflow.
- Nightly `schedule`: auxiliary gate. AVD startup, native-bridge checks, or the translated JNI smoke failure marks the standalone workflow red.

## Non-Goals

- Do not claim full ARM64 VMP correctness from this lane.
- Do not run protected private ARM64 libraries directly unless the private repo later provides a dedicated harness or APK.
- Do not add this work to the current `ci.yml` glibc/bionic gate.
- Do not remove the existing private glibc/bionic jobs as the authoritative host-side signal.

## Architecture

Keep a separate `.github/workflows/avd-smoke.yml` workflow on `ubuntu-latest`. It boots a cached `x86_64` `google_apis` AVD with KVM acceleration, clones the private repo for provenance, and probes the repo for both `x86_64` and `arm64` shared-library candidates. After the emulator boots, the workflow runs two layers of validation:

1. Device environment smoke through `adb`: runtime properties, native-bridge property, `libndk_translation.so` presence, `/data/local/tmp` advisory behavior, and on-device shell execution.
2. A minimal translated JNI load smoke: build a tiny APK in the workflow, package an `arm64-v8a` JNI library, install it into the `x86_64` AVD, launch the app, and require log evidence that `JNI_OnLoad` ran through the translation path.

The workflow writes `avd-smoke-report.json`, `avd-device-tests.json`, `avd-project-probe.json`, `avd-native-bridge-smoke.json`, and uploads them plus `logcat` and the smoke APK.

## Data Flow

1. Resolve `target_ref` from workflow input or default to `main`.
2. Clone private source through `DEPLOY_KEY` and `PRIVATE_REPO_URL`.
3. Resolve the checked-out private commit SHA.
4. Probe the private repo for APK/AAB/Gradle/manifest signals plus `.so` architecture breakdown.
5. Restore an `x86_64` AVD snapshot cache keyed by API level, target, ABI, and profile.
6. On cache miss, create the AVD once and let emulator-runner save the default snapshot.
7. Boot the cached AVD with KVM.
8. Run required device smoke:
   - `adb get-state` is `device`
   - SDK and ABI properties are readable
   - `ro.dalvik.vm.native.bridge` is enabled
   - `libndk_translation.so` is present somewhere in the system image
   - a small shell script can run on-device
9. Record `/data/local/tmp` create/delete behavior as an advisory signal only.
10. Build `native-bridge-smoke.apk` inside the workflow:
   - compile one `arm64-v8a` JNI library
   - compile one tiny Activity that calls `System.loadLibrary`
   - package and sign the APK
11. Install the APK, launch it, and require log evidence for:
   - `JNI_OnLoad reached`
   - `after System.loadLibrary`
   - `MainActivity.onCreate`
12. Write `avd-native-bridge-smoke.json` and embed it in the main report.
13. Upload the reports, APK, and `logcat`.

## Failure Semantics

- Manual dispatch uses job-level `continue-on-error`, so failed smoke remains exploratory.
- Scheduled nightly runs fail the standalone workflow on AVD boot, device smoke, or native-bridge harness failure.
- The lane proves native-bridge availability and one minimal translated JNI execution path only; it still does not prove full private ARM64 VMP compatibility.

## Testing

Static validation:

- YAML parses with Python `PyYAML`.
- Workflow still has isolated `workflow_dispatch` and `schedule` triggers.
- Validation script requires the native-bridge harness build script, smoke script, and artifact upload.
- `scripts/test_avd_project_probe.py` covers the shared-library architecture breakdown.

Runtime validation is expected in GitHub Actions because local execution cannot boot the hosted AVD environment.
