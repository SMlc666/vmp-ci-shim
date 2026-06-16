# CPP Business Android Native-Bridge Design

Date: 2026-06-16
Status: Approved for implementation
Scope: Replace the toy translated JNI smoke in `vmp-ci-shim` with a full Android native-bridge smoke that runs the real `tests/realib_fixtures/cpp_business` battery from the private `android_vmp` repo.

## Goal

Promote the current `x86_64` KVM AVD + `libndk_translation` lane from a minimal JNI canary to a full translated business-fixture smoke:

- build the private `cpp_business` fixture as `arm64-v8a` Android native code with the NDK
- execute the full battery inside the `x86_64` emulator through Android native bridge
- pass only when the translated battery finishes with `BATTERY-FAILS=0`

## Non-Goals

- Do not replace the existing host-side glibc/bionic real-lib gates.
- Do not prove full private VMP correctness across all protected libraries.
- Do not introduce a separate duplicated Android-only battery logic path.
- Do not require a full Gradle application in the private repo.

## Architecture

The private repo `android_vmp` becomes the source of truth for business-fixture execution logic. The current host battery implementation under `tests/realib_fixtures/cpp_business/` is split into:

1. A shared runner that owns all case execution, PASS/FAIL line emission, and final `BATTERY-FAILS` accounting.
2. A host CLI entrypoint that preserves the existing `dlopen`-driven battery path by delegating to the shared runner.
3. A JNI bridge entrypoint that loads the same exported fixture symbols and invokes the same shared runner from Android.

`vmp-ci-shim` remains responsible for Android-side orchestration only:

1. clone the private repo for provenance and source access
2. invoke the private `cpp_business` NDK build path
3. package the resulting `arm64-v8a` JNI library and `libcpp_business.so` into a small smoke APK
4. install and launch the APK in the cached `x86_64` AVD
5. capture the full runner output and fail unless `BATTERY-FAILS=0`

This preserves one behavioral source of truth while giving both host and translated-Android paths equal test semantics.

## Repo Responsibilities

### Private repo: `android_vmp`

Files under `tests/realib_fixtures/cpp_business/` are extended to support both host and Android translated execution:

- extract the existing battery case body into `cpp_business_runner.*`
- keep `cpp_business_battery.cpp` as a thin host entrypoint
- add `cpp_business_jni.cpp` as a thin Android entrypoint
- extend `build.sh` with an NDK-capable mode that emits Android `arm64-v8a` artifacts

The pass contract stays identical: complete output plus terminal `BATTERY-FAILS=N`.

### Public repo: `vmp-ci-shim`

The existing AVD smoke lane is retargeted from the toy JNI test to the real private fixture:

- replace the toy harness assets in `.github/native_bridge_smoke/`
- call the private build path instead of compiling a dummy C file
- parse the translated runner output for `PASS:*`, `FAIL:*`, and `BATTERY-FAILS=0`

## Data Flow

1. `vmp-ci-shim` clones private `android_vmp` into `src/`.
2. The workflow probes private artifacts and confirms `cpp_business` inputs exist.
3. The emulator boots on `x86_64` with `libndk_translation.so` available.
4. The workflow invokes `src/tests/realib_fixtures/cpp_business/build.sh` in Android/NDK mode.
5. The build emits:
   - translated target library artifacts for `arm64-v8a`
   - a JNI-facing Android shared library that delegates to the shared runner
6. `vmp-ci-shim` packages those artifacts into the smoke APK.
7. The APK is installed and launched in the AVD.
8. JNI calls the shared runner.
9. The shared runner executes the complete `cpp_business` battery and emits the canonical output.
10. `vmp-ci-shim` captures `logcat` / app output and fails unless:
   - runner started
   - runner completed
   - `BATTERY-FAILS=0`

## Failure Semantics

Fail closed in every ambiguous case:

- missing native bridge property: fail
- missing `libndk_translation.so`: fail
- private Android NDK build failure: fail
- APK packaging failure: fail
- app launch failure: fail
- JNI bridge not reached: fail
- no battery summary line: fail
- `BATTERY-FAILS != 0`: fail

`/data/local/tmp` remains advisory only, because the lane’s real purpose is translated `cpp_business` execution, not tmpfs behavior.

## Testing

### Static / local

- keep `scripts/test_avd_project_probe.py`
- add focused tests for any new parser that validates `BATTERY-FAILS=0`
- keep workflow structure validation in `scripts/validate-avd-smoke-workflow.py`
- add syntax checks for new JNI packaging/orchestration scripts

### Runtime

Runtime proof must come from GitHub Actions hosted execution:

- the AVD must report `ro.dalvik.vm.native.bridge=libndk_translation.so`
- the smoke APK must install and launch
- the translated battery must end with `BATTERY-FAILS=0`

## Rationale

This route is heavier than the toy JNI probe, but it is the smallest design that actually tests the private business fixture under Android translated execution without splitting battery logic into divergent host and Android copies.
