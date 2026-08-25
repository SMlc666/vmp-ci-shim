#!/usr/bin/env bash
set -u -o pipefail

log_path=${TEST_LOG:-/tmp/test.log}
: > "$log_path"

if [[ $# -eq 0 ]]; then
  echo "E2E_RUNNER_FAILURE: no test targets supplied" | tee -a "$log_path"
  exit 1
fi

run_target() {
  local target=$1
  local label=$2
  local build_rc=0
  local run_rc=0
  local target_dir=${CARGO_TARGET_DIR:-target}

  if [[ "$target_dir" != /* ]]; then
    target_dir="$PWD/$target_dir"
  fi

  echo "=== building e2e target $target ===" | tee -a "$log_path"
  cargo test -p vmp-lifter --test "$target" --no-run --quiet 2>&1 | tee -a "$log_path"
  build_rc=${PIPESTATUS[0]}

  if [[ $build_rc -eq 0 ]]; then
    local binary
    binary=$(find "$target_dir/debug/deps" -maxdepth 1 -type f \
      -name "${target}-*" -perm -111 -printf '%T@ %p\n' \
      | sort -n | tail -1 | cut -d' ' -f2-)
    if [[ -z "$binary" ]]; then
      echo "E2E_RUNNER_FAILURE: no executable for $target under $target_dir/debug/deps" \
        | tee -a "$log_path"
      run_rc=127
    else
      echo "=== running e2e target $target ===" | tee -a "$log_path"
      "$binary" --nocapture 2>&1 | tee -a "$log_path"
      run_rc=${PIPESTATUS[0]}
    fi
  else
    run_rc=$build_rc
  fi

  echo "[$label] cargo_status = $run_rc" | tee -a "$log_path"
}

while [[ $# -gt 0 ]]; do
  target=$1
  label=$2
  shift 2
  run_target "$target" "$label"
done

# The gate script consumes every recorded status and emits one final result.
# Keeping this runner green lets all independent suites run and produce useful
# diagnostics instead of stopping at the first test target.
exit 0
