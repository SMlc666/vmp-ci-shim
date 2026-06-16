# CPP Business Android Native-Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the real private `tests/realib_fixtures/cpp_business` battery inside the `x86_64` AVD through Android native bridge and pass only when `BATTERY-FAILS=0`.

**Architecture:** Move the `cpp_business` battery logic into a shared runner in `android_vmp`, keep the current host CLI as a thin wrapper, add a JNI wrapper that calls the same runner, then change `vmp-ci-shim` to build/package/run that Android target instead of the toy JNI smoke.

**Tech Stack:** GitHub Actions, bash, adb, Android SDK build-tools, Android NDK, C++17, JNI, Python.

---

### Task 1: Extract Shared CPP Business Runner In `android_vmp`

**Files:**
- Create: `/root/android_vmp/tests/realib_fixtures/cpp_business/cpp_business_runner.hpp`
- Create: `/root/android_vmp/tests/realib_fixtures/cpp_business/cpp_business_runner.cpp`
- Modify: `/root/android_vmp/tests/realib_fixtures/cpp_business/cpp_business_battery.cpp`
- Test: `/root/android_vmp/vmp-lifter/tests/realib_cpp_business_e2e.rs`

- [ ] **Step 1: Write the failing host regression test**

Add a focused Rust-side assertion in `realib_cpp_business_e2e.rs` that the host battery output still contains `BATTERY-FAILS=0` and the same `PASS:*` contract after the refactor.

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
cd /root/android_vmp
VMP_REALIB_E2E=1 cargo test -p vmp-lifter --test realib_cpp_business_e2e cpp_business_suite_policy_native_no_regressions -- --nocapture
```

Expected: fail once `cpp_business_battery.cpp` is converted to a thin wrapper before the shared runner exists.

- [ ] **Step 3: Create the shared runner API**

Define one host/JNI-neutral API that accepts:

- a symbol loader callback
- a temp-dir provider
- a log sink callback

and returns:

- `fails`
- the full emitted text

The API should own:

- all `emit_case(...)` logic
- all symbol names and expected values
- final `BATTERY-FAILS=N` formatting

- [ ] **Step 4: Rewrite the host battery as a thin wrapper**

Keep `main(argc, argv)` and `dlopen`, but delegate all business-case execution to the shared runner.

- [ ] **Step 5: Re-run the host regression test**

Run:

```bash
cd /root/android_vmp
tests/realib_fixtures/cpp_business/build.sh
tests/realib_fixtures/cpp_business/build/cpp_business_battery tests/realib_fixtures/cpp_business/build/libcpp_business.so
VMP_REALIB_E2E=1 cargo test -p vmp-lifter --test realib_cpp_business_e2e cpp_business_suite_policy_native_no_regressions -- --nocapture
```

Expected: host battery still prints `BATTERY-FAILS=0`; focused Rust test passes.

### Task 2: Add JNI Entry And Android Build Mode In `android_vmp`

**Files:**
- Create: `/root/android_vmp/tests/realib_fixtures/cpp_business/cpp_business_jni.cpp`
- Modify: `/root/android_vmp/tests/realib_fixtures/cpp_business/build.sh`
- Possibly create: `/root/android_vmp/tests/realib_fixtures/cpp_business/android_manifest_stub.txt` only if build scripting needs fixed metadata

- [ ] **Step 1: Write the failing Android-build probe**

Add a shell-level verification target that expects `build.sh` to support an Android/NDK mode and emit:

- `build/android/arm64-v8a/libcpp_business.so`
- `build/android/arm64-v8a/libcpp_business_jni.so`

- [ ] **Step 2: Run the probe to verify it fails**

Run:

```bash
cd /root/android_vmp
ANDROID_NDK_HOME=/tmp/does-not-exist tests/realib_fixtures/cpp_business/build.sh --android-arm64
```

Expected: current script rejects the mode or lacks the artifacts.

- [ ] **Step 3: Add JNI wrapper**

Implement one JNI function that:

- creates/uses an app-private temp dir path supplied from Java
- loads `libcpp_business.so` exports through direct linking or `dlsym` as chosen in the implementation
- calls the shared runner
- returns the full runner text to Java

- [ ] **Step 4: Extend `build.sh`**

Add an Android/NDK build mode that:

- preserves current host build behavior by default
- uses NDK clang++ for `aarch64-linux-android21+`
- builds `libcpp_business.so`
- builds `libcpp_business_jni.so`
- stages headers and outputs under `build/android/arm64-v8a/`

- [ ] **Step 5: Verify Android outputs exist**

Run with a real local NDK path if available:

```bash
cd /root/android_vmp
ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/27.2.12479018" tests/realib_fixtures/cpp_business/build.sh --android-arm64
find tests/realib_fixtures/cpp_business/build/android -maxdepth 3 -type f | sort
```

Expected: both Android `.so` artifacts appear.

### Task 3: Replace Toy Harness Assets In `vmp-ci-shim`

**Files:**
- Modify: `/root/vmp-ci-shim/.github/native_bridge_smoke/AndroidManifest.xml`
- Modify: `/root/vmp-ci-shim/.github/native_bridge_smoke/MainActivity.java`
- Delete or stop using: `/root/vmp-ci-shim/.github/native_bridge_smoke/bridge_jni.c`
- Modify: `/root/vmp-ci-shim/.github/scripts/build-native-bridge-harness.sh`

- [ ] **Step 1: Write a failing public-side packaging test**

Add a focused Python or shell test that expects the harness builder to package:

- `libcpp_business.so`
- `libcpp_business_jni.so`

instead of the toy `libbridge_smoke.so`.

- [ ] **Step 2: Run the packaging test to verify it fails**

Run the focused harness-builder test in `/root/vmp-ci-shim`.

Expected: current builder still references `bridge_jni.c` and fails the new expectation.

- [ ] **Step 3: Convert the Java harness**

Replace the toy Activity with one that:

- loads `cpp_business_jni`
- determines an app-private temp directory
- calls the JNI method
- logs the returned runner text under a stable tag

- [ ] **Step 4: Rework the builder**

Update `build-native-bridge-harness.sh` so it:

- locates the checked-out private repo under `src/`
- invokes `src/tests/realib_fixtures/cpp_business/build.sh --android-arm64`
- packages the private Android outputs into `native-bridge-smoke.apk`

- [ ] **Step 5: Verify packaging logic locally**

Run syntax checks plus any focused test added in Step 1.

### Task 4: Replace Minimal JNI Success Criteria With Full Battery Criteria

**Files:**
- Modify: `/root/vmp-ci-shim/.github/scripts/avd-native-bridge-smoke.py`
- Modify: `/root/vmp-ci-shim/.github/scripts/avd-smoke-report.sh`
- Modify: `/root/vmp-ci-shim/scripts/validate-avd-smoke-workflow.py`

- [ ] **Step 1: Write a failing parser test**

Add a focused test for a parser/helper that accepts sample log text only when:

- `BATTERY-FAILS=0` exists
- no required completion marker is missing

- [ ] **Step 2: Run the parser test to verify it fails**

Run the focused parser test in `/root/vmp-ci-shim`.

Expected: current implementation only checks for `JNI_OnLoad` and `MainActivity.onCreate`.

- [ ] **Step 3: Implement full-battery validation**

Update `avd-native-bridge-smoke.py` to:

- capture the JNI-returned runner text and/or logcat output
- require the final `BATTERY-FAILS=0`
- include a truncated but useful excerpt in `avd-native-bridge-smoke.json`

- [ ] **Step 4: Update the top-level report and validator**

Make the main report describe the new scope precisely and require the workflow validator to enforce the private-build-driven harness path.

- [ ] **Step 5: Run focused tests**

Run the parser test and workflow validator again.

### Task 5: Run End-To-End Verification

**Files:**
- Validate both repos together

- [ ] **Step 1: Verify local static checks**

Run:

```bash
cd /root/vmp-ci-shim
python3 scripts/validate-avd-smoke-workflow.py
python3 -m py_compile .github/scripts/avd-device-tests.py .github/scripts/avd-project-probe.py .github/scripts/avd-native-bridge-smoke.py scripts/validate-avd-smoke-workflow.py
sh -n .github/scripts/avd-smoke-report.sh .github/scripts/build-native-bridge-harness.sh
```

Expected: all pass silently except the validator message `avd smoke workflow ok`.

- [ ] **Step 2: Verify private host path still works**

Run:

```bash
cd /root/android_vmp
tests/realib_fixtures/cpp_business/build.sh
tests/realib_fixtures/cpp_business/build/cpp_business_battery tests/realib_fixtures/cpp_business/build/libcpp_business.so
```

Expected: host path still ends with `BATTERY-FAILS=0`.

- [ ] **Step 3: Trigger GitHub Actions runtime validation**

Run:

```bash
cd /root/vmp-ci-shim
gh workflow run "AVD Smoke" --ref <working-branch>
gh run watch <run-id> --interval 15
```

Expected: translated Android run succeeds and `avd-native-bridge-smoke.json` records `BATTERY-FAILS=0`.
