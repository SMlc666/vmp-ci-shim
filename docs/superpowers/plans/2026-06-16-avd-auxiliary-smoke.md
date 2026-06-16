# AVD Native-Bridge Smoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the standalone Android Emulator lane into an x86_64 KVM + native-bridge/libndk smoke that proves one translated `arm64-v8a` JNI load path.

**Architecture:** Keep the isolated `avd-smoke.yml` workflow, preserve the cached `x86_64` KVM AVD boot path, and add two new layers: native-bridge environment assertions plus a source-controlled minimal APK whose `arm64-v8a` JNI library is loaded inside the emulator. Keep the private glibc/bionic jobs as the authoritative CI gate.

**Tech Stack:** GitHub Actions, `reactivecircus/android-emulator-runner`, `actions/setup-java`, bash, adb, Python, Android SDK build-tools, Android NDK.

---

### Task 1: Expand Private Repo Probe

**Files:**
- Modify: `.github/scripts/avd-project-probe.py`
- Test: `scripts/test_avd_project_probe.py`

- [x] **Step 1: Write the failing test**

Require the probe to report both `x86_64` AVD candidates and `arm64` Android shared-library candidates.

- [x] **Step 2: Run test to verify it fails**

Run: `python3 -m unittest scripts/test_avd_project_probe.py`
Expected: fail because `android_arm64_shared_lib_count` is missing.

- [x] **Step 3: Write minimal implementation**

Add `android_arm64_candidate`, `android_arm64_shared_lib_count`, and `android_arm64_shared_libs` while preserving the existing `x86_64` view.

- [x] **Step 4: Run test to verify it passes**

Run: `python3 -m unittest scripts/test_avd_project_probe.py`
Expected: PASS

### Task 2: Add Native-Bridge Harness Assets

**Files:**
- Create: `.github/native_bridge_smoke/AndroidManifest.xml`
- Create: `.github/native_bridge_smoke/MainActivity.java`
- Create: `.github/native_bridge_smoke/bridge_jni.c`
- Create: `.github/scripts/build-native-bridge-harness.sh`
- Create: `.github/scripts/avd-native-bridge-smoke.py`

- [x] **Step 1: Add source-controlled smoke assets**

Create a tiny Activity that calls `System.loadLibrary("bridge_smoke")` and one `arm64-v8a` JNI library that logs from `JNI_OnLoad`.

- [x] **Step 2: Add APK build script**

Use Android SDK build-tools plus Android NDK to compile, package, align, and sign `native-bridge-smoke.apk`.

- [x] **Step 3: Add runtime smoke script**

Install the APK, launch the Activity, and require log evidence that translated JNI load and Activity startup both happened.

### Task 3: Extend Device Smoke and Main Report

**Files:**
- Modify: `.github/scripts/avd-device-tests.py`
- Modify: `.github/scripts/avd-smoke-report.sh`

- [x] **Step 1: Add native-bridge environment checks**

Require `ro.dalvik.vm.native.bridge` to be enabled and `libndk_translation.so` to exist in the guest image.

- [x] **Step 2: Run harness build + smoke from the report helper**

Build the APK, run the translated JNI smoke, record `avd-native-bridge-smoke.json`, and merge it into `avd-smoke-report.json`.

- [x] **Step 3: Preserve failure semantics**

Keep `/data/local/tmp` advisory only, but fail the workflow when required environment checks or the harness smoke fail.

### Task 4: Update Workflow and Static Validation

**Files:**
- Modify: `.github/workflows/avd-smoke.yml`
- Modify: `scripts/validate-avd-smoke-workflow.py`

- [x] **Step 1: Add Java/tooling assumption**

Install JDK 17 so the smoke harness can compile and sign the APK.

- [x] **Step 2: Upload new artifacts**

Require `avd-native-bridge-smoke.json` and `native-bridge-smoke.apk` in workflow artifacts.

- [x] **Step 3: Tighten static validation**

Require the helper to build and run the native-bridge harness and require the new artifact upload.

### Task 5: Verify Locally

**Files:**
- Validate: `.github/workflows/avd-smoke.yml`
- Validate: `.github/scripts/*.py`
- Validate: `.github/scripts/*.sh`

- [x] **Step 1: Run focused checks**

Run:

```bash
python3 -m unittest scripts/test_avd_project_probe.py
python3 scripts/validate-avd-smoke-workflow.py
python3 -m py_compile .github/scripts/avd-device-tests.py .github/scripts/avd-project-probe.py .github/scripts/avd-native-bridge-smoke.py scripts/validate-avd-smoke-workflow.py
sh -n .github/scripts/avd-smoke-report.sh .github/scripts/build-native-bridge-harness.sh
```

Expected output: tests pass, validator prints `avd smoke workflow ok`, and syntax checks are silent.
