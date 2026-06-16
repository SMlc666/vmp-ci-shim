# AVD Auxiliary Smoke Design

Date: 2026-06-16
Status: Approved for implementation
Scope: Add an Android Virtual Device lane to `vmp-ci-shim` without changing the existing glibc/bionic CI gate.

## Goal

Add an AVD-based auxiliary signal with two operating modes:

- Manual `workflow_dispatch`: non-blocking smoke. AVD failures are reported in artifacts but do not replace or weaken the existing `CI` workflow.
- Nightly `schedule`: auxiliary gate. AVD startup or smoke failure fails the standalone AVD workflow so it is visible in Actions history.

## Non-Goals

- Do not claim ARM64 VMP device compatibility from this lane.
- Do not run protected ARM64 `.so` files inside the AVD.
- Do not add AVD work to the current `ci.yml` glibc/bionic workflow.
- Do not require KVM.

## Architecture

Create a separate `.github/workflows/avd-smoke.yml` workflow. It runs on `ubuntu-latest`, enables `/dev/kvm`, restores a cached x86_64 AVD snapshot when available, and uses `reactivecircus/android-emulator-runner` both to seed the cache on misses and to boot the cached emulator for smoke execution. The workflow collects basic Android runtime properties through `adb`, runs device-side smoke tests, writes machine-readable `avd-smoke-report.json` and `avd-device-tests.json`, and uploads the reports plus `logcat`. The emulator runner invokes only a single POSIX `sh` helper command because the action executes `script:` lines one-by-one through `/usr/bin/sh`.
Before booting the emulator, the workflow also scans the checked-out private repo for Android delivery signals such as APKs, AABs, manifests, Gradle build files, and shared libraries, and records the result in `avd-project-probe.json`.

The workflow clones the private source repository only to bind the smoke result to a target private ref and commit SHA. Manual runs accept `target_ref`; scheduled runs default to `main`.

## Data Flow

1. Resolve `target_ref` from workflow input or default to `main`.
2. Clone private source through `DEPLOY_KEY` and `PRIVATE_REPO_URL`.
3. Resolve the checked-out private commit SHA.
4. Enable `/dev/kvm` access on the GitHub Linux runner.
5. Restore an AVD snapshot cache keyed by API level, target, ABI, and profile.
6. On cache miss, create the AVD once and let emulator-runner save the default snapshot.
7. Boot the cached AVD.
8. Run `adb` probes:
   - `getprop ro.build.version.sdk`
   - `getprop ro.product.cpu.abi`
   - `getprop ro.product.cpu.abilist`
   - `/system/bin/linker64` existence
9. Run device-side smoke tests:
   - `adb get-state` is `device`
   - SDK and ABI properties are readable
   - `/data/local/tmp` create/delete behavior is recorded as an advisory signal, not a hard gate
   - a small shell script can run on-device through `/system/bin/sh`
10. Write `avd-device-tests.json` and embed the test summary in `avd-smoke-report.json`.
11. Probe the checked-out private repo for Android artifact signals and write `avd-project-probe.json`.
12. Upload the reports and `logcat`.

## Failure Semantics

- Manual dispatch uses job-level `continue-on-error`, so failed AVD smoke does not produce a hard workflow failure.
- Scheduled nightly runs do not use `continue-on-error`, so failure marks `AVD Smoke` red.
- Existing `CI` workflow remains the authoritative glibc/bionic gate.

## Testing

Static validation:

- YAML parses with Python `PyYAML`.
- Workflow has both `workflow_dispatch` and `schedule`.
- Workflow contains no `pull_request` or `push` trigger, so it cannot slow normal pushes.

Runtime validation is expected in GitHub Actions because local execution cannot boot the hosted AVD environment.
