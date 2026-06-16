# AVD Auxiliary Smoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an isolated Android Emulator smoke workflow with manual non-blocking mode and nightly auxiliary-gate mode, and make it run a small device-side smoke test suite.

**Architecture:** Create a new `.github/workflows/avd-smoke.yml` workflow rather than modifying the current `ci.yml`. The workflow resolves a private repo ref, probes the checked-out private repo for Android delivery signals, enables Linux KVM access, restores an AVD snapshot cache, seeds that cache on misses, boots the cached x86_64 AVD, collects adb/runtime facts, runs device-side smoke tests, writes `avd-smoke-report.json`, `avd-device-tests.json`, and `avd-project-probe.json`, and uploads artifacts. Manual runs are job-level `continue-on-error`; scheduled runs fail the standalone workflow when smoke fails.

**Tech Stack:** GitHub Actions, `reactivecircus/android-emulator-runner`, `webfactory/ssh-agent`, bash, adb, Python `PyYAML` for static validation.

---

### Task 1: Document AVD Scope

**Files:**
- Create: `docs/superpowers/specs/2026-06-16-avd-auxiliary-smoke-design.md`

- [x] **Step 1: Write the design spec**

Write a concise design documenting the two modes, non-goals, failure semantics, and validation plan.

- [x] **Step 2: Review the spec for ambiguity**

Confirm the spec does not claim ARM64 VMP compatibility from an x86_64/no-KVM AVD.

### Task 2: Add AVD Smoke Workflow

**Files:**
- Create: `.github/workflows/avd-smoke.yml`

- [x] **Step 1: Add workflow triggers**

Define `workflow_dispatch` with `target_ref` and a nightly cron schedule. Do not add `push` or `pull_request`.

- [x] **Step 2: Clone private source**

Use the existing deploy-key pattern from `ci.yml`, clone `PRIVATE_REPO_URL`, check out `target_ref`, and record `PRIVATE_SHA`.

- [ ] **Step 2c: Probe private repo Android artifacts**

Scan the checked-out private repo for APK/AAB files, Gradle build files, manifests, and shared libraries. Save the result to `avd-project-probe.json` and embed it into the main AVD report.

- [ ] **Step 2b: Add KVM + snapshot cache**

Add the standard Linux KVM udev rule, cache `~/.android/avd/*` plus `~/.android/adb*`, and seed the cache with a dedicated emulator-runner step on cache miss.

- [x] **Step 3: Boot AVD and collect report**

Use `reactivecircus/android-emulator-runner@v2` with an x86_64 image, `-no-metrics`, `-no-snapshot-save`, a restored snapshot cache, and a single POSIX-`sh` helper invocation. Collect SDK, ABI, ABI list, linker64 existence, and write JSON.

- [ ] **Step 3b: Run device-side smoke tests**

Check adb device state, property reads, and an on-device shell-script execution path as hard-gate smoke tests. Record `/data/local/tmp` create/delete behavior as an advisory signal in `avd-device-tests.json`, but do not fail the workflow on that case alone.

- [x] **Step 4: Upload artifacts**

Always upload `avd-smoke-report.json`, `avd-device-tests.json`, `avd-project-probe.json`, and `avd-logcat.txt` with 14-day retention.

### Task 3: Validate Workflow

**Files:**
- Validate: `.github/workflows/avd-smoke.yml`

- [x] **Step 1: Parse YAML**

Run:

```bash
python3 scripts/validate-avd-smoke-workflow.py
python3 - <<'PY'
import yaml
yaml.safe_load(open(".github/workflows/avd-smoke.yml", encoding="utf-8"))
print("yaml ok")
PY
```

Expected output:

```text
yaml ok
```

- [x] **Step 2: Verify trigger isolation**

Run:

```bash
grep -nE "push:|pull_request:" .github/workflows/avd-smoke.yml || true
```

Expected output: empty.

- [x] **Step 3: Review diff**

Run:

```bash
git diff -- .github/workflows/avd-smoke.yml docs/superpowers
```

Expected: only the new workflow and docs are changed.
