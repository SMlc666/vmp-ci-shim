#!/usr/bin/env bash
set -uo pipefail

# The benchmark runner owns measurement semantics; this shim only checks its
# provenance/report contract and maps report status to a stable CI exit class.
readonly EXPECTED_DOTNET_SDK="8.0.424"
readonly EXPECTED_SCHEMA_VERSION=1
readonly EXPECTED_RUN_KIND="csharp-performance"

source_dir=${SOURCE_DIR:-}
source_sha=${SOURCE_SHA:-}
log_path=${CSHARP_PERFORMANCE_LOG:-${CSHARP_LOG:-/tmp/csharp-performance.log}}
report_path=${CSHARP_PERFORMANCE_REPORT:-${CSHARP_PERFORMANCE_RESULT:-${CSHARP_RESULT:-${CSHARP_REPORT:-/tmp/csharp-performance.json}}}}

usage() {
  printf 'usage: csharp-performance-gate.sh SOURCE_DIR SOURCE_SHA [LOG_PATH] [REPORT_PATH]\n' >&2
  printf '       csharp-performance-gate.sh --source-dir DIR --source-sha SHA [--log PATH] [--report PATH]\n' >&2
}

if [[ $# -gt 0 && "$1" != --* ]]; then
  source_dir=$1
  shift
  if [[ $# -gt 0 && "$1" != --* ]]; then
    source_sha=$1
    shift
  fi
  if [[ $# -gt 0 && "$1" != --* ]]; then
    log_path=$1
    shift
  fi
  if [[ $# -gt 0 && "$1" != --* ]]; then
    report_path=$1
    shift
  fi
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir|--source)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      source_dir=$2
      shift 2
      ;;
    --source-sha|--sha)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      source_sha=$2
      shift 2
      ;;
    --log|--log-path)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      log_path=$2
      shift 2
      ;;
    --report|--report-path|--result)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      report_path=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'CSHARP_PERFORMANCE_GATE_FAILURE: unknown argument: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$source_dir" || -z "$source_sha" ]]; then
  printf 'CSHARP_PERFORMANCE_GATE_FAILURE: source directory and full source SHA are required\n' >&2
  usage
  exit 2
fi

if [[ ! "$source_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
  printf 'CSHARP_PERFORMANCE_GATE_FAILURE: source SHA must be a full 40-character SHA\n' >&2
  exit 2
fi

# Resolve output paths before changing directory for dotnet SDK resolution.
if [[ "$log_path" != /* ]]; then
  log_path="$PWD/$log_path"
fi
if [[ "$report_path" != /* ]]; then
  report_path="$PWD/$report_path"
fi
if [[ "$source_dir" != /* ]]; then
  source_dir="$PWD/$source_dir"
fi

if [[ ! -d "$source_dir" ]]; then
  printf 'CSHARP_PERFORMANCE_GATE_FAILURE: source directory does not exist: %s\n' "$source_dir" >&2
  exit 2
fi
source_dir=$(cd -- "$source_dir" && pwd -P) || {
  printf 'CSHARP_PERFORMANCE_GATE_FAILURE: unable to resolve source directory: %s\n' "$source_dir" >&2
  exit 2
}

log_parent=$(dirname -- "$log_path")
report_parent=$(dirname -- "$report_path")
if [[ ! -d "$log_parent" || ! -d "$report_parent" ]]; then
  printf 'CSHARP_PERFORMANCE_GATE_FAILURE: log/report parent directory is missing\n' >&2
  exit 2
fi
if ! : > "$log_path"; then
  printf 'CSHARP_PERFORMANCE_GATE_FAILURE: cannot create log: %s\n' "$log_path" >&2
  exit 2
fi

log_line() {
  printf '%s\n' "$*" | tee -a "$log_path"
}

fail_gate() {
  local code=$1
  local step=$2
  local detail=$3
  [[ "$code" -gt 0 ]] || code=1
  printf 'CSHARP_PERFORMANCE_GATE_FAILURE: step=%s status=%s detail=%s\n' \
    "$step" "$code" "$detail" | tee -a "$log_path" >&2
  exit "$code"
}

actual_source_sha=""
log_line '=== source provenance ==='
if [[ ! -e "$source_dir/.git" ]]; then
  fail_gate 1 source-provenance 'private source is not a Git checkout'
fi
actual_source_sha=$(git -C "$source_dir" rev-parse --verify HEAD 2>>"$log_path") || \
  fail_gate 1 source-provenance 'unable to resolve source HEAD'
actual_source_sha=${actual_source_sha,,}
if [[ ! "$actual_source_sha" =~ ^[0-9a-f]{40}$ ]]; then
  fail_gate 1 source-provenance \
    "source HEAD is not an exact 40-character SHA: $actual_source_sha"
fi
if [[ "$actual_source_sha" != "${source_sha,,}" ]]; then
  fail_gate 1 source-provenance \
    "checked out $actual_source_sha, expected ${source_sha,,}"
fi
log_line "SOURCE_SHA_OK: $actual_source_sha"

benchmark_project="$source_dir/cs/benchmarks/Vmp.Lifter.PerformanceBench"
if [[ ! -f "$benchmark_project/Vmp.Lifter.PerformanceBench.csproj" ]]; then
  fail_gate 1 benchmark-source \
    'missing checked-in cs/benchmarks/Vmp.Lifter.PerformanceBench project'
fi

# A temporary global.json prevents a runner image's newer SDK from satisfying
# this gate through roll-forward or a machine-wide installation.
dotnet_root=$(mktemp -d "${TMPDIR:-/tmp}/csharp-performance-dotnet.XXXXXX") || \
  fail_gate 1 sdk-probe 'unable to create temporary SDK resolution directory'
trap 'rm -rf -- "$dotnet_root"' EXIT
cat > "$dotnet_root/global.json" <<EOF_GLOBAL_JSON
{
  "sdk": {
    "version": "$EXPECTED_DOTNET_SDK",
    "rollForward": "disable",
    "allowPrerelease": false
  }
}
EOF_GLOBAL_JSON
log_line "DOTNET_GLOBAL_JSON: $dotnet_root/global.json"

log_line '=== SDK probe ==='
dotnet_bin=$(command -v dotnet || true)
if [[ -z "$dotnet_bin" || ! -x "$dotnet_bin" ]]; then
  fail_gate 1 sdk-probe 'dotnet executable is missing'
fi
set +e
dotnet_version_output=$(cd -- "$dotnet_root" && DOTNET_MULTILEVEL_LOOKUP=0 \
  "$dotnet_bin" --version 2>&1)
version_code=$?
set -u
printf '%s\n' "$dotnet_version_output" | tee -a "$log_path"
if [[ "$version_code" -ne 0 ]]; then
  fail_gate 1 sdk-probe 'dotnet --version failed'
fi
dotnet_version=$(printf '%s\n' "$dotnet_version_output" | tail -n 1 | tr -d '\r')
if [[ "$dotnet_version" != "$EXPECTED_DOTNET_SDK" ]]; then
  fail_gate 1 sdk-probe \
    "effective SDK=$dotnet_version, expected $EXPECTED_DOTNET_SDK"
fi
log_line "DOTNET_SDK_OK: $dotnet_version"

# Never accept a report left by an earlier invocation when the new runner
# fails before writing its artifact.
if ! rm -f -- "$report_path"; then
  fail_gate 1 report-output "cannot remove stale report: $report_path"
fi

log_line '=== csharp performance benchmark (Release quick CI --all) ==='
set +e
(
  cd -- "$dotnet_root" && DOTNET_MULTILEVEL_LOOKUP=0 "$dotnet_bin" run \
    --project "$benchmark_project" \
    --configuration Release \
    -- \
    --all \
    --mode quick \
    --ci \
    --repo-root "$source_dir" \
    --source-commit "$source_sha" \
    --output "$report_path"
) 2>&1 | tee -a "$log_path"
runner_code=${PIPESTATUS[0]}
set -u
log_line "BENCHMARK_PROCESS_EXIT: $runner_code"

if [[ ! -f "$report_path" ]]; then
  fail_gate 1 benchmark-run \
    "benchmark did not produce report (process status $runner_code)"
fi

# Validate the report independently of the benchmark process exit code. A
# fake/older dotnet wrapper may return zero after writing a non-passing report,
# but the report status must still be preserved and mapped below.
set +e
validation_output=$(python3 - "$report_path" "${source_sha,,}" "$runner_code" \
  "$EXPECTED_SCHEMA_VERSION" "$EXPECTED_RUN_KIND" <<'PY'
import json
import pathlib
import sys


class ReportError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ReportError(message)


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def nonempty_string(value, field):
    require(isinstance(value, str) and bool(value.strip()), f"{field} must be a non-empty string")
    return value


report_path = pathlib.Path(sys.argv[1])
expected_source = sys.argv[2].lower()
try:
    runner_code = int(sys.argv[3])
    expected_schema_version = int(sys.argv[4])
    expected_run_kind = sys.argv[5]
except ValueError as exc:
    raise ReportError(f"invalid benchmark process status: {sys.argv[3]!r}") from exc

try:
    with report_path.open(encoding="utf-8") as stream:
        report = json.load(stream)
except (OSError, UnicodeError, json.JSONDecodeError) as exc:
    raise ReportError(f"unable to parse JSON report: {exc}") from exc

require(isinstance(report, dict), "report root must be a JSON object")
required_top_level = (
    "schema_version",
    "run_kind",
    "mode",
    "ci_mode",
    "status",
    "provenance",
    "selected_case_ids",
    "selected_case_count",
    "results",
    "blocked_case_count",
    "error_case_count",
    "regression_case_count",
    "exit_code",
)
for field in required_top_level:
    require(field in report, f"report is missing required field {field}")

require(report["schema_version"] == expected_schema_version, "unsupported benchmark report schema_version")
require(report["run_kind"] == expected_run_kind, "unexpected benchmark run_kind")
require(report["mode"] == "quick", "performance gate requires quick mode")
require(report["ci_mode"] is True, "performance gate requires ci_mode=true")

status = report["status"]
allowed_statuses = {"informational", "match", "blocked", "regression", "error"}
require(isinstance(status, str) and status in allowed_statuses,
        f"unknown report status {status!r}")

provenance = report["provenance"]
require(isinstance(provenance, dict), "provenance must be a JSON object")
source_commit = nonempty_string(provenance.get("source_commit"), "provenance.source_commit")
require(source_commit.lower() == expected_source, "report source_commit does not match checked out source HEAD")
for field in ("target_framework", "runtime_version", "process_architecture", "runner_version"):
    nonempty_string(provenance.get(field), f"provenance.{field}")

selected_ids = report["selected_case_ids"]
require(isinstance(selected_ids, list), "selected_case_ids must be an array")
require(selected_ids and all(isinstance(value, str) and value for value in selected_ids),
        "selected_case_ids must contain at least one non-empty string")
require(len(set(selected_ids)) == len(selected_ids), "selected_case_ids must be unique")
selected_count = report["selected_case_count"]
require(is_int(selected_count) and selected_count > 0,
        "selected_case_count must be a positive integer")
require(selected_count == len(selected_ids),
        "selected_case_count does not match selected_case_ids")

results = report["results"]
require(isinstance(results, list), "results must be an array")
require(len(results) == selected_count,
        f"result count {len(results)} does not match selected_case_count {selected_count}")

result_ids = []
for index, result in enumerate(results):
    require(isinstance(result, dict), f"results[{index}] must be an object")
    case_id = nonempty_string(result.get("case_id"), f"results[{index}].case_id")
    result_ids.append(case_id)
    row_status = result.get("status")
    require(isinstance(row_status, str) and row_status in allowed_statuses,
            f"results[{index}] has unknown status {row_status!r}")
    preflight = result.get("preflight")
    require(isinstance(preflight, dict), f"results[{index}].preflight must be an object")
    preflight_status = preflight.get("status")
    require(isinstance(preflight_status, str)
            and preflight_status in {"ready", "blocked", "error"},
            f"results[{index}].preflight.status is invalid")

require(len(set(result_ids)) == len(result_ids), "results must not contain duplicate case IDs")
require(set(result_ids) == set(selected_ids),
        "result case IDs must match selected_case_ids")

blocked_rows = []
error_rows = []
regression_rows = []
for result in results:
    case_id = result["case_id"]
    row_status = result["status"]
    preflight = result["preflight"]
    preflight_status = preflight["status"]
    if row_status == "blocked":
        require(preflight_status == "blocked",
                f"blocked case {case_id} must retain blocked preflight status")
        reason = nonempty_string(preflight.get("reason"),
                                 f"blocked case {case_id} reason")
        capability = preflight.get("capability")
        diagnostic = preflight.get("diagnostic")
        if capability is not None:
            nonempty_string(capability, f"blocked case {case_id} capability")
        if diagnostic is not None:
            nonempty_string(diagnostic, f"blocked case {case_id} diagnostic")
        first_error = nonempty_string(result.get("first_error"),
                                      f"blocked case {case_id} first_error")
        blocked_rows.append((case_id, reason, capability, diagnostic, first_error))
    elif row_status == "error":
        nonempty_string(result.get("first_error"), f"error case {case_id} first_error")
        error_rows.append(case_id)
        require(preflight_status == "error" or preflight_status == "ready",
                f"error case {case_id} has invalid preflight status")
    else:
        require(preflight_status == "ready",
                f"measured case {case_id} must retain ready preflight status")
        measurement = result.get("measurement")
        validation = result.get("validation")
        require(isinstance(measurement, dict),
                f"measured case {case_id} is missing measurement")
        require(isinstance(validation, dict) and validation.get("succeeded") is True,
                f"measured case {case_id} did not retain successful validation")
        comparison = result.get("comparison")
        if row_status == "regression":
            require(isinstance(comparison, dict) and comparison.get("status") == "regression",
                    f"regression case {case_id} is missing regression comparison")
            regression_rows.append(case_id)
        elif row_status == "match":
            require(isinstance(comparison, dict) and comparison.get("status") == "match",
                    f"matching case {case_id} is missing match comparison")
        elif row_status == "informational" and comparison is not None:
            require(isinstance(comparison, dict) and comparison.get("status") == "informational",
                    f"informational case {case_id} has an invalid comparison")

expected_status = (
    "error" if error_rows
    else "regression" if regression_rows
    else "blocked" if blocked_rows
    else "informational" if any(result["status"] == "informational" for result in results)
    else "match"
)
require(status == expected_status,
        f"report status {status!r} does not match result rows ({expected_status!r})")

for field, expected in (
    ("blocked_case_count", len(blocked_rows)),
    ("error_case_count", len(error_rows)),
    ("regression_case_count", len(regression_rows)),
):
    require(is_int(report[field]) and report[field] == expected,
            f"{field} does not match result rows")

exit_code = report["exit_code"]
require(is_int(exit_code), "exit_code must be an integer")
if status in {"informational", "match"}:
    require(exit_code == 0, "informational/match reports require exit_code 0")
    require(runner_code == 0, "benchmark process failed for an informational/match report")
elif status == "blocked":
    require(exit_code == 3, "blocked reports require exit_code 3")
    require(runner_code in {0, 3}, "benchmark process status disagrees with blocked report")
elif status == "regression":
    require(exit_code == 4, "regression reports require exit_code 4")
    require(runner_code in {0, 4}, "benchmark process status disagrees with regression report")
else:
    require(exit_code != 0, "error reports require a nonzero exit_code")

print(
    f"REPORT_SCHEMA_OK: schema=1 status={status} "
    f"selected={selected_count} results={len(results)} "
    f"blocked={len(blocked_rows)} errors={len(error_rows)} regressions={len(regression_rows)}"
)
for case_id, reason, capability, diagnostic, first_error in blocked_rows:
    detail = f"BLOCKED_CASE: {case_id} reason={reason}"
    if capability:
        detail += f" capability={capability}"
    if diagnostic:
        detail += f" diagnostic={diagnostic}"
    # The first error is checked above; retain it in the log without changing
    # the source report so CI diagnostics include both stable reason fields.
    if first_error != reason:
        detail += f" first_error={first_error}"
    print(detail)

if status == "error":
    print("CSHARP_PERFORMANCE_REPORT_ERROR: report contains error rows", file=sys.stderr)
    raise SystemExit(1)
if status == "blocked":
    raise SystemExit(3)
if status == "regression":
    raise SystemExit(4)
raise SystemExit(0)
PY
)
validator_code=$?
set -u
printf '%s\n' "$validation_output" | tee -a "$log_path"
case "$validator_code" in
  0|3|4)
    exit "$validator_code"
    ;;
  *)
    printf 'CSHARP_PERFORMANCE_GATE_FAILURE: malformed/error benchmark report\n' \
      | tee -a "$log_path" >&2
    exit 1
    ;;
esac
