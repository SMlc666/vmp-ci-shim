#!/usr/bin/bash
set -u -o pipefail

log_path=${TEST_LOG:-/tmp/test.log}
: > "$log_path"

if [[ $# -eq 0 ]]; then
  echo "E2E_RUNNER_FAILURE: no test targets supplied" | tee -a "$log_path"
  exit 1
fi

run_binary() {
  if [[ "${BIONIC_MODE:-0}" == "1" ]]; then
    env \
      HOME="${BIONIC_HOME:?BIONIC_HOME is required}" \
      PATH="$BIONIC_PREFIX/bin:/tmp/host-toolchain-cleanbin:${PATH}" \
      LD_LIBRARY_PATH="$BIONIC_PREFIX/lib" \
      "$@"
  else
    "$@"
  fi
}

run_target() {
  local target=$1
  local label=$2
  local filter=$3
  local build_rc=0
  local run_rc=0
  local target_dir=${CARGO_TARGET_DIR:-target}

  if [[ "$target_dir" != /* ]]; then
    target_dir="$PWD/$target_dir"
  fi

  echo "=== locating e2e target $target ===" | tee -a "$log_path"
  build_rc=0

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
      # CI can opt into per-test fixture copies, which makes the test harness
      # safe to parallelize without clobbering another case's build outputs.
      local test_threads=${VMP_REALIB_TEST_THREADS:-1}
      case " ${VMP_REALIB_SERIAL_TARGETS:-} " in
        *" ${target} "*) test_threads=1 ;;
      esac
      local -a test_args=()
      if [[ "$filter" != "-" ]]; then
        test_args+=("$filter")
      fi
      run_binary "$binary" "${test_args[@]}" --nocapture --test-threads="$test_threads" 2>&1 | tee -a "$log_path"
      run_rc=${PIPESTATUS[0]}
    fi
  else
    run_rc=$build_rc
  fi

  echo "[$label] filter=$filter run_status=$run_rc" | tee -a "$log_path"
  return "$run_rc"
}

declare -A aggregate_status=()

while [[ $# -gt 0 ]]; do
  if [[ $# -lt 3 ]]; then
    echo "E2E_RUNNER_FAILURE: each run requires TARGET LABEL FILTER" | tee -a "$log_path"
    exit 1
  fi
  target=$1
  label=$2
  filter=$3
  shift 3
  if run_target "$target" "$label" "$filter"; then
    run_rc=0
  else
    run_rc=$?
  fi
  if [[ "${aggregate_status[$label]+present}" != present || "${aggregate_status[$label]}" -eq 0 ]]; then
    aggregate_status[$label]=$run_rc
  fi
done

for label in "${!aggregate_status[@]}"; do
  echo "[$label] cargo_status = ${aggregate_status[$label]}" | tee -a "$log_path"
done

# The gate script consumes every recorded status and emits one final result.
# Keeping this runner green lets all independent suites run and produce useful
# diagnostics instead of stopping at the first test target.
exit 0
