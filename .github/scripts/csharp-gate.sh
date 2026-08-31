#!/usr/bin/env bash
# Run the C# host gate against one immutable private-source checkout.
set -uo pipefail

usage() {
  echo "usage: csharp-gate.sh SOURCE_SHA [SOURCE_DIR] [LOG_PATH] [JSON_PATH]" >&2
}

workspace_root=$(pwd -P)
source_sha=${1:-${COMMIT_SHA:-${SOURCE_SHA:-}}}
source_dir_arg=${2:-${CSPROJ_SOURCE_DIR:-${SOURCE_DIR:-src}}}
artifact_dir=${RUNNER_TEMP:-${TMPDIR:-/tmp}}
log_path=${3:-${CSPROJ_GATE_LOG:-${CSHARP_GATE_LOG:-${GATE_LOG:-${LOG_PATH:-$artifact_dir/csharp-glibc-unit.log}}}}}
json_path=${4:-${CSPROJ_GATE_JSON:-${CSHARP_GATE_JSON:-${GATE_JSON:-${PROVENANCE_JSON:-$artifact_dir/csharp-glibc-unit.json}}}}}
job_name=${CSPROJ_JOB_NAME:-${CSHARP_JOB:-${JOB_NAME:-csharp_glibc_unit}}}
layer=${CSPROJ_LAYER:-${CSHARP_LAYER:-${LAYER:-unit}}}
required_sdk_family=${CSPROJ_DOTNET_SDK_FAMILY:-${DOTNET_SDK_FAMILY:-8.0}}
required_sdk_version=${CSPROJ_DOTNET_SDK_VERSION:-${DOTNET_SDK_VERSION:-}}
dotnet_bin=${CSPROJ_DOTNET_BIN:-${DOTNET_BIN:-dotnet}}
solution=${CSPROJ_SOLUTION:-cs/Vmp.sln}
asmstone_path=${CSPROJ_ASMSTONE_PATH:-${ASMSTONE_PATH:-third_party/AsmStone}}
catalog_lock=${CSPROJ_ASMSTONE_LOCK:-${ASMSTONE_LOCK:-third_party/AsmStone/spec/source-lock.json}}

if [[ $# -gt 4 ]]; then
  usage
  exit 2
fi

# Accept source-first forms as well, which are convenient for local callers;
# the workflow uses the documented SHA-first form.
if [[ $# -eq 1 && -d "$1" && ! "$1" =~ ^[0-9a-fA-F]{40}$ && -n "${COMMIT_SHA:-${SOURCE_SHA:-}}" ]]; then
  source_dir_arg=$1
  source_sha=${COMMIT_SHA:-${SOURCE_SHA:-}}
elif [[ $# -ge 2 && ! "$source_sha" =~ ^[0-9a-fA-F]{40}$ && "$2" =~ ^[0-9a-fA-F]{40}$ ]]; then
  source_dir_arg=$1
  source_sha=$2
fi

absolute_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$workspace_root" "$1" ;;
  esac
}

log_path=$(absolute_path "$log_path")
json_path=$(absolute_path "$json_path")

first_failure=0
first_failure_step=""
failure_reason=""
log_ready=0
log_write_failed=0
log_write_status=ok
source_dir_abs=""
expected_source_sha=""
actual_source_sha=""
detached=false
attached_ref=""
gitlink_sha=""
asmstone_commit=""
asmstone_status="not-run"
asmstone_catalog_sha=""
asmstone_generated_catalog_sha=""
asmstone_catalog_path="$asmstone_path"
asmstone_catalog_file_sha=""
sdk_version=""
dotnet_resolved=""
restore_status="not-run"
restore_rc=""
build_status="not-run"
build_rc=""
test_status="not-run"
test_rc=""
test_count=0
focus_records=""

# Keep the log and result creation independent of the source validation so that
# an invalid dispatch still leaves a machine-readable failure receipt.
log_parent=$(dirname -- "$log_path")
if mkdir -p -- "$log_parent" 2>/dev/null && : > "$log_path" 2>/dev/null; then
  log_ready=1
fi

append_log() {
  local line=$1
  if [[ "$log_ready" -eq 1 ]] && printf '%s\n' "$line" >> "$log_path" 2>/dev/null; then
    return 0
  fi
  log_write_failed=1
  log_write_status=error
  return 1
}

emit() {
  local line=$1
  printf '%s\n' "$line"
  append_log "$line" || true
}

record_failure() {
  local rc=$1
  local step=$2
  local reason=$3
  if [[ "$rc" -eq 0 ]]; then
    rc=1
  fi
  if [[ "$first_failure" -eq 0 ]]; then
    first_failure=$rc
    first_failure_step=$step
    failure_reason=$reason
  fi
  emit "GATE_FAILURE: step=$step status=$rc reason=$reason"
}

command_text() {
  printf '%q ' "$@"
}

# Run one command, preserving its exit status while teeing all output into the
# required log. The caller decides whether a nonzero status is fatal.
# The receipt remains writable after a failed dotnet restore/build/test command.
run_capture() {
  local label=$1
  local output_file=$2
  shift 2
  local rc=0
  emit "COMMAND[$label] $(command_text "$@")"
  if "$@" > "$output_file" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [[ -f "$output_file" ]]; then
    cat "$output_file"
    if [[ "$log_ready" -eq 1 ]]; then
      cat "$output_file" >> "$log_path" 2>/dev/null || { log_write_failed=1; log_write_status=error; }
    else
      log_write_failed=1
      log_write_status=error
    fi
  else
    emit "COMMAND_OUTPUT_MISSING: step=$label path=$output_file"
    if [[ "$rc" -eq 0 ]]; then
      rc=2
    fi
  fi
  return "$rc"
}

run_source_capture() {
  local label=$1
  local output_file=$2
  shift 2
  run_capture "$label" "$output_file" bash -c \
    'cd -- "$1" && shift && exec "$@"' csharp-gate "$source_dir_abs" "$@"
}

make_temp_dir() {
  local base=${TMPDIR:-/tmp}
  temp_dir=$(mktemp -d "$base/csharp-gate.XXXXXX" 2>/dev/null || true)
  if [[ -z "$temp_dir" || ! -d "$temp_dir" ]]; then
    temp_dir=""
    record_failure 2 temp "could not create temporary directory"
    return 1
  fi
  return 0
}

temp_dir=""
cleanup() {
  if [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
    rm -rf -- "$temp_dir"
  fi
}
trap cleanup EXIT

emit "C# gate start: job=$job_name layer=$layer source_sha=$source_sha source_dir=$source_dir_arg"

if [[ "$source_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
  expected_source_sha=${source_sha,,}
else
  record_failure 2 source_sha "source SHA must be a full 40-character hexadecimal commit"
fi

if [[ -d "$source_dir_arg" ]]; then
  source_dir_abs=$(cd -- "$source_dir_arg" 2>/dev/null && pwd -P || true)
fi
if [[ -z "$source_dir_abs" || ! -d "$source_dir_abs" ]]; then
  record_failure 3 source_checkout "source checkout directory is missing: $source_dir_arg"
fi

if [[ "$first_failure" -eq 0 ]]; then
  make_temp_dir || true
fi

if [[ "$first_failure" -eq 0 ]]; then
  head_output="$temp_dir/source-head.txt"
  if run_capture source_head "$head_output" git -C "$source_dir_abs" rev-parse --verify HEAD; then
    actual_source_sha=$(tr -d '\r' < "$head_output" | tail -n 1)
    if [[ ! "$actual_source_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
      record_failure 3 source_checkout "source HEAD is not a full commit SHA: $actual_source_sha"
    elif [[ "${actual_source_sha,,}" != "$expected_source_sha" ]]; then
      record_failure 1 source_checkout "checked out source $actual_source_sha, expected $expected_source_sha"
    else
      actual_source_sha=${actual_source_sha,,}
      emit "SOURCE_CHECKOUT_OK: $actual_source_sha"
    fi
  else
    rc=$?
    record_failure "$rc" source_checkout "git could not resolve source HEAD"
  fi
fi

if [[ "$first_failure" -eq 0 ]]; then
  detached_output="$temp_dir/source-ref.txt"
  if run_capture source_ref "$detached_output" git -C "$source_dir_abs" symbolic-ref --quiet --short HEAD; then
    attached_ref=$(tr -d '\r' < "$detached_output" | tail -n 1)
    record_failure 1 source_checkout "source checkout is attached to branch $attached_ref"
  else
    rc=$?
    if [[ "$rc" -eq 1 ]]; then
      detached=true
      emit "SOURCE_DETACHED_OK"
    else
      record_failure "$rc" source_checkout "could not determine whether source checkout is detached"
    fi
  fi
fi

if [[ "$first_failure" -eq 0 ]]; then
  source_status_output="$temp_dir/source-status.txt"
  if run_capture source_status "$source_status_output" \
      git -C "$source_dir_abs" status --porcelain --untracked-files=all; then
    if [[ -s "$source_status_output" ]]; then
      record_failure 1 source_checkout "source checkout has uncommitted or untracked files"
    fi
  else
    rc=$?
    record_failure "$rc" source_checkout "could not verify source checkout cleanliness"
  fi
fi

if [[ "$first_failure" -eq 0 ]]; then
  gitlink_output="$temp_dir/asmstone-gitlink.txt"
  if run_capture asmstone_gitlink "$gitlink_output" git -C "$source_dir_abs" ls-tree HEAD -- "$asmstone_path"; then
    gitlink_sha=$(awk '$1 == "160000" { count++; value=$3 } END { if (count == 1) print value }' "$gitlink_output")
    if [[ ! "$gitlink_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
      record_failure 4 submodule "AsmStone is not an exact gitlink at $asmstone_path"
    else
      gitlink_sha=${gitlink_sha,,}
      emit "ASMSTONE_GITLINK_OK: $gitlink_sha"
    fi
  else
    rc=$?
    record_failure "$rc" submodule "could not inspect AsmStone gitlink at $asmstone_path"
  fi
fi

if [[ "$first_failure" -eq 0 ]]; then
  # A fresh private clone reports an uninitialized submodule with a leading
  # dash. A leading plus or U means the checkout was changed and must fail
  # rather than being silently repaired into a different provenance state.
  pre_status_output="$temp_dir/asmstone-pre-status.txt"
  if run_capture asmstone_pre_status "$pre_status_output" \
      git -C "$source_dir_abs" submodule status -- "$asmstone_path"; then
    pre_status_line=$(sed -n '1p' "$pre_status_output")
    if [[ "$pre_status_line" =~ ^[+U] ]]; then
      record_failure 4 submodule "AsmStone checkout does not match its gitlink: $pre_status_line"
    fi
  else
    rc=$?
    record_failure "$rc" submodule "could not read AsmStone submodule status before initialization"
  fi
fi

if [[ "$first_failure" -eq 0 ]]; then
  if run_capture asmstone_update "$temp_dir/asmstone-update.txt" \
      git -C "$source_dir_abs" submodule update --init --recursive -- "$asmstone_path"; then
    :
  else
    rc=$?
    record_failure "$rc" submodule "AsmStone submodule initialization failed"
  fi
fi

asmstone_dir="$source_dir_abs/$asmstone_path"
if [[ "$first_failure" -eq 0 ]]; then
  submodule_status_output="$temp_dir/asmstone-status.txt"
  if run_capture asmstone_status "$submodule_status_output" \
      git -C "$source_dir_abs" submodule status -- "$asmstone_path"; then
    status_line=$(sed -n '1p' "$submodule_status_output")
    if [[ "$status_line" =~ ^[-+U] ]]; then
      record_failure 4 submodule "AsmStone submodule is not initialized at its gitlink: $status_line"
    fi
  else
    rc=$?
    record_failure "$rc" submodule "could not read AsmStone submodule status"
  fi
fi

if [[ "$first_failure" -eq 0 ]]; then
  submodule_head_output="$temp_dir/asmstone-head.txt"
  if run_capture asmstone_commit "$submodule_head_output" \
      git -C "$asmstone_dir" rev-parse --verify HEAD; then
    asmstone_commit=$(tr -d '\r' < "$submodule_head_output" | tail -n 1)
    if [[ ! "$asmstone_commit" =~ ^[0-9a-fA-F]{40}$ ]]; then
      record_failure 4 submodule "AsmStone HEAD is not a full commit SHA: $asmstone_commit"
    elif [[ "${asmstone_commit,,}" != "$gitlink_sha" ]]; then
      record_failure 1 submodule "AsmStone commit $asmstone_commit does not match gitlink $gitlink_sha"
    else
      asmstone_commit=${asmstone_commit,,}
      asmstone_worktree_output="$temp_dir/asmstone-worktree-status.txt"
      if run_capture asmstone_worktree_status "$asmstone_worktree_output" \
          git -C "$asmstone_dir" status --porcelain --untracked-files=all; then
        if [[ -s "$asmstone_worktree_output" ]]; then
          record_failure 1 submodule "AsmStone checkout has uncommitted or untracked files"
        fi
      else
        rc=$?
        record_failure "$rc" submodule "could not verify AsmStone checkout cleanliness"
      fi
      if [[ "$first_failure" -eq 0 ]]; then
        asmstone_status=passed
        emit "ASMSTONE_COMMIT_OK: $asmstone_commit"
      fi
    fi
  else
    rc=$?
    record_failure "$rc" submodule "could not resolve AsmStone submodule HEAD"
  fi
fi

if [[ "$first_failure" -eq 0 ]]; then
  catalog_file="$source_dir_abs/$catalog_lock"
  if [[ -n "${CSPROJ_ASMSTONE_CATALOG_SHA256:-${ASMSTONE_CATALOG_SHA256:-}}" ]]; then
    asmstone_catalog_sha=${CSPROJ_ASMSTONE_CATALOG_SHA256:-${ASMSTONE_CATALOG_SHA256:-}}
  fi
  if [[ -n "${CSPROJ_ASMSTONE_GENERATED_CATALOG_SHA256:-${ASMSTONE_GENERATED_CATALOG_SHA256:-}}" ]]; then
    asmstone_generated_catalog_sha=${CSPROJ_ASMSTONE_GENERATED_CATALOG_SHA256:-${ASMSTONE_GENERATED_CATALOG_SHA256:-}}
  fi
  if [[ -f "$catalog_file" ]]; then
    # Keep both the TableGen input identity and generated catalog identity.
    if [[ -z "$asmstone_catalog_sha" ]]; then
      asmstone_catalog_sha=$(grep -Eo '"tablegenJsonSha256"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]{64}"' \
        "$catalog_file" | head -n 1 | grep -Eo '[0-9a-fA-F]{64}' | tail -n 1)
    fi
    if [[ -z "$asmstone_generated_catalog_sha" ]]; then
      asmstone_generated_catalog_sha=$(grep -Eo '"generatedCatalogSha256"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]{64}"' \
        "$catalog_file" | head -n 1 | grep -Eo '[0-9a-fA-F]{64}' | tail -n 1)
    fi
    # Older fixture locks may contain only the generated hash. Preserve their
    # compatibility while preferring the TableGen input hash for new records.
    if [[ -z "$asmstone_catalog_sha" ]]; then
      asmstone_catalog_sha=$asmstone_generated_catalog_sha
    fi
    asmstone_catalog_file_sha=$(sha256sum "$catalog_file" 2>/dev/null | awk '{print $1}')
  fi
  if [[ ! "$asmstone_catalog_sha" =~ ^[0-9a-fA-F]{64}$
      || ( -n "$asmstone_generated_catalog_sha" && ! "$asmstone_generated_catalog_sha" =~ ^[0-9a-fA-F]{64}$ ) ]]; then
    record_failure 4 submodule "AsmStone catalog SHA-256 identity is missing or invalid"
  else
    asmstone_catalog_sha=${asmstone_catalog_sha,,}
    asmstone_generated_catalog_sha=${asmstone_generated_catalog_sha,,}
    emit "ASMSTONE_CATALOG_OK: $asmstone_catalog_sha"
    if [[ -n "$asmstone_generated_catalog_sha" ]]; then
      emit "ASMSTONE_GENERATED_CATALOG_OK: $asmstone_generated_catalog_sha"
    fi
  fi
fi

if [[ "$first_failure" -eq 0 ]]; then
  if [[ "$dotnet_bin" == */* ]]; then
    if [[ -x "$dotnet_bin" ]]; then
      dotnet_resolved=$(cd "$(dirname -- "$dotnet_bin")" 2>/dev/null && pwd -P)/$(basename -- "$dotnet_bin")
    fi
  else
    dotnet_resolved=$(command -v "$dotnet_bin" 2>/dev/null || true)
  fi
  if [[ -z "$dotnet_resolved" || ! -x "$dotnet_resolved" ]]; then
    record_failure 5 sdk "dotnet executable is missing: $dotnet_bin"
  fi
fi

if [[ "$first_failure" -eq 0 ]]; then
  sdk_output="$temp_dir/dotnet-version.txt"
  if run_capture dotnet_version "$sdk_output" "$dotnet_resolved" --version; then
    sdk_version=$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' "$sdk_output" | tail -n 1)
    sdk_pattern="^${required_sdk_family//./\\.}\\.[0-9]+$"
    if [[ ! "$sdk_version" =~ $sdk_pattern ]]; then
      record_failure 5 sdk "dotnet SDK $sdk_version is outside required family $required_sdk_family"
    elif [[ -n "$required_sdk_version" && "$sdk_version" != "$required_sdk_version" ]]; then
      record_failure 5 sdk "dotnet SDK $sdk_version does not match required version $required_sdk_version"
    else
      emit "DOTNET_SDK_OK: $sdk_version"
    fi
  else
    rc=$?
    record_failure "$rc" sdk "dotnet --version failed"
  fi
fi

# The required command sequence is dotnet restore, dotnet build
# --configuration Release, and dotnet test --configuration Release --no-build.
# In shell form: dotnet restore; dotnet build --configuration Release; dotnet test --configuration Release --no-build.

if [[ "$first_failure" -eq 0 ]]; then
  mkdir -p -- "$temp_dir/results/solution"
  restore_output="$temp_dir/restore.txt"
  if run_source_capture restore "$restore_output" "$dotnet_resolved" restore "$solution"; then
    restore_status=passed
    restore_rc=0
  else
    restore_rc=$?
    restore_status=failed
    record_failure "$restore_rc" restore "dotnet restore failed"
  fi
fi

if [[ "$first_failure" -eq 0 ]]; then
  build_output="$temp_dir/build.txt"
  if run_source_capture build "$build_output" "$dotnet_resolved" build "$solution" \
      --configuration Release --no-restore; then
    build_status=passed
    build_rc=0
  else
    build_rc=$?
    build_status=failed
    record_failure "$build_rc" build "dotnet build failed"
  fi
fi

# Parse the standard "Total tests: N"/"Total: N" summaries or TRX counters.
extract_test_count() {
  local output_file=$1
  local result_dir=$2
  local count=0
  local found=0
  local number

  if [[ -f "$output_file" ]]; then
    while read -r number; do
      [[ "$number" =~ ^[0-9]+$ ]] || continue
      count=$((count + number))
      found=1
    done < <(grep -Eio 'total[[:space:]_]*tests?[[:space:]:=]+[0-9]+' "$output_file" \
      | grep -Eo '[0-9]+$' || true)
    if [[ "$found" -eq 0 ]]; then
      while read -r number; do
        [[ "$number" =~ ^[0-9]+$ ]] || continue
        count=$((count + number))
        found=1
      done < <(grep -Eio 'total[[:space:]]*:[[:space:]]*[0-9]+' "$output_file" \
        | grep -Eo '[0-9]+$' || true)
    fi
  fi

  if [[ "$found" -eq 0 && -d "$result_dir" ]]; then
    while IFS= read -r trx; do
      number=$(sed -n 's/.*executed="\([0-9][0-9]*\)".*/\1/p' "$trx" | head -n 1)
      if [[ -z "$number" ]]; then
        number=$(grep -o '<UnitTestResult[[:space:]]' "$trx" | wc -l | tr -d ' ')
      fi
      if [[ "$number" =~ ^[0-9]+$ ]]; then
        count=$((count + number))
        found=1
      fi
    done < <(find "$result_dir" -type f -name '*.trx' -print 2>/dev/null)
  fi

  printf '%s\n' "$count"
}

run_focus_gate() {
  local label=$1
  local project=$2
  local filter=$3
  local safe_label=${label//[^a-zA-Z0-9_.-]/_}
  local output="$temp_dir/focus-${safe_label}.txt"
  local result_dir="$temp_dir/results/${safe_label}"
  local status=not-run
  local rc=""
  local count=0
  mkdir -p -- "$result_dir"

  if [[ "$first_failure" -ne 0 ]]; then
    focus_records+="${label}"$'\t'"${status}"$'\t'"${rc}"$'\t'"${count}"$'\n'
    return 0
  fi

  local -a focus_args=(
    "$dotnet_resolved" test "$project"
    --configuration Release --no-build --no-restore
    --logger "trx;LogFileName=${safe_label}.trx"
    --results-directory "$result_dir"
  )
  if [[ -n "$filter" ]]; then
    focus_args+=(--filter "$filter")
  fi
  if run_source_capture "focus-$label" "$output" "${focus_args[@]}"; then
    status=passed
    rc=0
  else
    rc=$?
    status=failed
    record_failure "$rc" "focus_$label" "C# focused gate failed"
  fi
  count=$(extract_test_count "$output" "$result_dir")
  if [[ "$status" == passed && "$count" -eq 0 ]]; then
    status=failed
    record_failure 1 "focus_$label" "focused gate executed zero tests"
  fi
  focus_records+="${label}"$'\t'"${status}"$'\t'"${rc}"$'\t'"${count}"$'\n'
}

if [[ "$first_failure" -eq 0 ]]; then
  test_output="$temp_dir/test.txt"
  solution_results="$temp_dir/results/solution"
  if run_source_capture test "$test_output" "$dotnet_resolved" test "$solution" \
      --configuration Release --no-build --no-restore \
      --logger "trx;LogFileName=solution.trx" --results-directory "$solution_results"; then
    test_status=passed
    test_rc=0
  else
    test_rc=$?
    test_status=failed
    record_failure "$test_rc" test "dotnet test failed"
  fi
  test_count=$(extract_test_count "$test_output" "$solution_results")
  if [[ "$test_status" == passed && "$test_count" -eq 0 ]]; then
    test_status=failed
    record_failure 1 test_count "dotnet test selected zero tests"
  fi
fi

# Keep each high-signal C# gate named in the receipt. These are all host-side
# unit checks; no protected-ELF artifact or bionic consumer is part of this wave.
if [[ "$first_failure" -eq 0 ]]; then
  run_focus_gate raw_encoder_603_vectors \
    "${CSPROJ_RAW_ENCODER_PROJECT:-cs/tests/Vmp.Runtime.Native.Tests/Vmp.Runtime.Native.Tests.csproj}" \
    "${CSPROJ_RAW_ENCODER_FILTER:-FullyQualifiedName~ClassifiesEveryRawEncoderVector}"
  run_focus_gate asmstone_decoder_alias \
    "${CSPROJ_ASMSTONE_DECODER_PROJECT:-cs/tests/Vmp.Lifter.Decode.Tests/Vmp.Lifter.Decode.Tests.csproj}" \
    "${CSPROJ_ASMSTONE_DECODER_FILTER:-FullyQualifiedName~AsmStone}"
  run_focus_gate asmstone_adapter_alias \
    "${CSPROJ_ASMSTONE_ADAPTER_PROJECT:-cs/tests/Vmp.Lifter.Arm64.Tests/Vmp.Lifter.Arm64.Tests.csproj}" \
    "${CSPROJ_ASMSTONE_ADAPTER_FILTER:-FullyQualifiedName~AsmStone}"
  run_focus_gate nativeblob_policy \
    "${CSPROJ_NATIVE_BLOB_PROJECT:-cs/tests/Vmp.Runtime.Native.Tests/Vmp.Runtime.Native.Tests.csproj}" \
    "${CSPROJ_NATIVE_BLOB_FILTER:-FullyQualifiedName~NativeBlob}"
  run_focus_gate stage_local_function_parity \
    "${CSPROJ_STAGE_PARITY_PROJECT:-cs/tests/Vmp.Lifter.Tests/Vmp.Lifter.Tests.csproj}" \
    "${CSPROJ_STAGE_PARITY_FILTER:-FullyQualifiedName~StageLocal}"
fi

log_status=missing
log_bytes=0
if [[ -f "$log_path" ]]; then
  log_bytes=$(wc -c < "$log_path" | tr -d ' ')
fi
if [[ "$log_ready" -eq 1 && "$log_write_failed" -eq 0 && -s "$log_path" ]]; then
  log_status=present
else
  if [[ "$log_write_failed" -ne 0 ]]; then
    log_write_status=error
  fi
  if [[ "$first_failure" -eq 0 ]]; then
    record_failure 2 log "required gate log is missing or cannot be written"
  fi
fi

# Emit the terminal result before serializing provenance so the JSON byte count
# covers every line written by this gate.
if [[ "$first_failure" -eq 0 ]]; then
  emit "C# gate PASS: source=$expected_source_sha asmstone=$asmstone_commit sdk=$sdk_version tests=$test_count"
else
  emit "C# gate FAIL: first_failure=$first_failure step=$first_failure_step reason=$failure_reason"
fi
if [[ "$log_write_failed" -ne 0 && "$first_failure" -eq 0 ]]; then
  record_failure 2 log "required gate log write failed"
  log_write_status=error
  log_status=missing
fi
if [[ -f "$log_path" ]]; then
  log_bytes=$(wc -c < "$log_path" | tr -d ' ')
fi

json_status=missing
write_json() {
  local json_tmp="${json_path}.tmp.$$"
  local json_parent
  local python_bin=${CSPROJ_PYTHON_BIN:-python3}
  json_parent=$(dirname -- "$json_path")
  if ! mkdir -p -- "$json_parent" 2>/dev/null; then
    return 1
  fi
  if ! command -v "$python_bin" >/dev/null 2>&1; then
    return 1
  fi
  if \
    SOURCE_SHA_RAW="$source_sha" \
    EXPECTED_SOURCE_SHA="$expected_source_sha" \
    ACTUAL_SOURCE_SHA="$actual_source_sha" \
    SOURCE_DIR="$source_dir_abs" \
    DETACHED="$detached" \
    ATTACHED_REF="$attached_ref" \
    GITLINK_SHA="$gitlink_sha" \
    ASMSTONE_COMMIT="$asmstone_commit" \
    ASMSTONE_STATUS="$asmstone_status" \
    ASMSTONE_CATALOG_PATH="$asmstone_catalog_path" \
    ASMSTONE_CATALOG_SHA="$asmstone_catalog_sha" \
    ASMSTONE_GENERATED_CATALOG_SHA="$asmstone_generated_catalog_sha" \
    ASMSTONE_CATALOG_FILE_SHA="$asmstone_catalog_file_sha" \
    DOTNET_SDK="$sdk_version" \
    DOTNET_SDK_FAMILY="$required_sdk_family" \
    DOTNET_SDK_VERSION="$required_sdk_version" \
    DOTNET_BIN="$dotnet_resolved" \
    LAYER="$layer" \
    JOB_NAME="$job_name" \
    RESTORE_STATUS="$restore_status" \
    RESTORE_RC="$restore_rc" \
    BUILD_STATUS="$build_status" \
    BUILD_RC="$build_rc" \
    TEST_STATUS="$test_status" \
    TEST_RC="$test_rc" \
    TEST_COUNT="$test_count" \
    FOCUS_RECORDS="$focus_records" \
    LOG_PATH="$log_path" \
    LOG_STATUS="$log_status" \
    LOG_WRITE_STATUS="$log_write_status" \
    LOG_BYTES="$log_bytes" \
    FIRST_FAILURE="$first_failure" \
    FIRST_FAILURE_STEP="$first_failure_step" \
    FAILURE_REASON="$failure_reason" \
    "$python_bin" - "$json_tmp" <<'PY'
import json
import os
import sys


def integer(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def boolean(value):
    return value.lower() == "true"


def step(status, rc):
    return {"status": status, "exit_status": integer(rc)}

focus = []
for row in os.environ.get("FOCUS_RECORDS", "").splitlines():
    if not row:
        continue
    label, status, rc, count = (row.split("\t") + ["", "", "", ""])[:4]
    focus.append({
        "name": label,
        "status": status,
        "exit_status": integer(rc),
        "test_count": integer(count) or 0,
    })

failure = integer(os.environ.get("FIRST_FAILURE", "0")) or 0
result = "pass" if failure == 0 else "failure"
record = {
    "schema_version": 1,
    "status": result,
    "result": result,
    "gate_status": "success" if failure == 0 else "failure",
    "outcome": "success" if failure == 0 else "failure",
    "source_commit": os.environ.get("EXPECTED_SOURCE_SHA", ""),
    "source_sha": os.environ.get("EXPECTED_SOURCE_SHA", "") or os.environ.get("SOURCE_SHA_RAW", ""),
    "requested_source_sha": os.environ.get("SOURCE_SHA_RAW", ""),
    "checked_out_commit": os.environ.get("ACTUAL_SOURCE_SHA", ""),
    "source_directory": os.environ.get("SOURCE_DIR", ""),
    "detached": boolean(os.environ.get("DETACHED", "false")),
    "attached_ref": os.environ.get("ATTACHED_REF", ""),
    "checkout": {
        "status": "passed" if os.environ.get("ACTUAL_SOURCE_SHA", "") == os.environ.get("EXPECTED_SOURCE_SHA", "") and boolean(os.environ.get("DETACHED", "false")) else "failed",
        "expected_commit": os.environ.get("EXPECTED_SOURCE_SHA", ""),
        "actual_commit": os.environ.get("ACTUAL_SOURCE_SHA", ""),
        "detached": boolean(os.environ.get("DETACHED", "false")),
    },
    "source": {
        "status": "passed" if os.environ.get("ACTUAL_SOURCE_SHA", "") == os.environ.get("EXPECTED_SOURCE_SHA", "") and boolean(os.environ.get("DETACHED", "false")) else "failed",
        "expected_commit": os.environ.get("EXPECTED_SOURCE_SHA", ""),
        "actual_commit": os.environ.get("ACTUAL_SOURCE_SHA", ""),
    },
    "asmstone": {
        "path": os.environ.get("ASMSTONE_CATALOG_PATH", "third_party/AsmStone"),
        "gitlink": os.environ.get("GITLINK_SHA", ""),
        "commit": os.environ.get("ASMSTONE_COMMIT", ""),
        "status": os.environ.get("ASMSTONE_STATUS", "not-run"),
        "catalog_sha256": os.environ.get("ASMSTONE_CATALOG_SHA", ""),
        "generated_catalog_sha256": os.environ.get("ASMSTONE_GENERATED_CATALOG_SHA", ""),
        "catalog_file_sha256": os.environ.get("ASMSTONE_CATALOG_FILE_SHA", ""),
    },
    "asmstone_gitlink": os.environ.get("GITLINK_SHA", ""),
    "asmstone_commit": os.environ.get("ASMSTONE_COMMIT", ""),
    "asmstone_catalog_sha256": os.environ.get("ASMSTONE_CATALOG_SHA", ""),
    "asmstone_generated_catalog_sha256": os.environ.get("ASMSTONE_GENERATED_CATALOG_SHA", ""),
    "submodule": {
        "status": os.environ.get("ASMSTONE_STATUS", "not-run"),
        "path": os.environ.get("ASMSTONE_CATALOG_PATH", "third_party/AsmStone"),
        "gitlink": os.environ.get("GITLINK_SHA", ""),
        "commit": os.environ.get("ASMSTONE_COMMIT", ""),
        "catalog_sha256": os.environ.get("ASMSTONE_CATALOG_SHA", ""),
        "generated_catalog_sha256": os.environ.get("ASMSTONE_GENERATED_CATALOG_SHA", ""),
    },
    "dotnet": {
        "path": os.environ.get("DOTNET_BIN", ""),
        "sdk": os.environ.get("DOTNET_SDK", ""),
        "required_family": os.environ.get("DOTNET_SDK_FAMILY", ""),
        "required_version": os.environ.get("DOTNET_SDK_VERSION", ""),
    },
    "dotnet_sdk": os.environ.get("DOTNET_SDK", ""),
    "dotnet_sdk_family": os.environ.get("DOTNET_SDK_FAMILY", ""),
    "sdk": os.environ.get("DOTNET_SDK", ""),
    "sdk_check": {
        "status": "passed" if os.environ.get("DOTNET_SDK", "") else "failed",
        "version": os.environ.get("DOTNET_SDK", ""),
        "family": os.environ.get("DOTNET_SDK_FAMILY", ""),
    },
    "layer": os.environ.get("LAYER", ""),
    "job": os.environ.get("JOB_NAME", ""),
    "restore": step(os.environ.get("RESTORE_STATUS", "not-run"), os.environ.get("RESTORE_RC", "")),
    "build": step(os.environ.get("BUILD_STATUS", "not-run"), os.environ.get("BUILD_RC", "")),
    "test": {
        "status": os.environ.get("TEST_STATUS", "not-run"),
        "exit_status": integer(os.environ.get("TEST_RC", "")),
        "test_count": integer(os.environ.get("TEST_COUNT", "0")) or 0,
        "focused_gates": focus,
    },
    "test_count": integer(os.environ.get("TEST_COUNT", "0")) or 0,
    "tests_run": integer(os.environ.get("TEST_COUNT", "0")) or 0,
    "test_status": os.environ.get("TEST_STATUS", "not-run"),
    "log": {
        "path": os.environ.get("LOG_PATH", ""),
        "status": os.environ.get("LOG_STATUS", "missing"),
        "write_status": os.environ.get("LOG_WRITE_STATUS", "unknown"),
        "present": os.environ.get("LOG_STATUS", "missing") == "present",
        "bytes": integer(os.environ.get("LOG_BYTES", "0")) or 0,
    },
    "log_status": os.environ.get("LOG_STATUS", "missing"),
    "log_write_status": os.environ.get("LOG_WRITE_STATUS", "unknown"),
    "log_path": os.environ.get("LOG_PATH", ""),
    "log_exists": os.environ.get("LOG_STATUS", "missing") == "present",
    "log_ok": os.environ.get("LOG_STATUS", "missing") == "present",
    "failure_status": failure or None,
    "failure_step": os.environ.get("FIRST_FAILURE_STEP", ""),
    "failure_reason": os.environ.get("FAILURE_REASON", ""),
}
with open(sys.argv[1], "w", encoding="utf-8") as stream:
    json.dump(record, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY
  then
    if mv -f -- "$json_tmp" "$json_path" 2>/dev/null && [[ -s "$json_path" ]]; then
      json_status=present
      return 0
    fi
  fi
  rm -f -- "$json_tmp"
  return 1
}

if ! write_json; then
  if [[ "$first_failure" -eq 0 ]]; then
    record_failure 2 provenance "could not write JSON provenance output"
  fi
  # A second attempt records the provenance failure when the first write was
  # rejected by a transient output-directory problem.
  write_json || true
fi

if [[ "$json_status" != present && "$first_failure" -eq 0 ]]; then
  record_failure 2 provenance "JSON provenance output is missing"
  write_json || true
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '### C# glibc unit gate\n'
    printf '| field | value |\n|---|---|\n'
    printf '| result | %s |\n' "$([[ "$first_failure" -eq 0 ]] && echo pass || echo failure)"
    printf '| source commit | `%s` |\n' "$expected_source_sha"
    printf '| AsmStone commit | `%s` |\n' "$asmstone_commit"
    printf '| .NET SDK | `%s` |\n' "$sdk_version"
    printf '| tests executed | `%s` |\n' "$test_count"
    printf '| log | `%s` (%s bytes) |\n' "$log_status" "$log_bytes"
  } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'source_commit=%s\n' "$expected_source_sha"
    printf 'asmstone_commit=%s\n' "$asmstone_commit"
    printf 'dotnet_sdk=%s\n' "$sdk_version"
    printf 'test_count=%s\n' "$test_count"
    printf 'log_status=%s\n' "$log_status"
    printf 'json_path=%s\n' "$json_path"
    printf 'gate_status=%s\n' "$([[ "$first_failure" -eq 0 ]] && echo success || echo failure)"
  } >> "$GITHUB_OUTPUT" 2>/dev/null || true
fi

exit "$first_failure"
