#!/usr/bin/env bash
set -uo pipefail

# These pins are part of the C# compatibility gate, not caller-controlled
# inputs.  Updating one requires a reviewed source/provenance change.
readonly EXPECTED_DOTNET_SDK="8.0.424"
readonly EXPECTED_ASMSTONE_COMMIT="477e07eb58f26c6c05960a3f5e55a2f3798df8cb"
readonly EXPECTED_LLVM_COMMIT="87b1a2f7246bc0a4ed5335c45635bddb75847890"
readonly EXPECTED_CATALOG_SHA256="728f5eb9a7fb5d04f417e61e7f74181db7c17f1afebf512131c188be1066b82f"
readonly EXPECTED_ASMSTONE_LICENSE_SHA256="f238b19e6b9fecb0ad94dd585b1f6cedd2e49c97f4c556c6281c0341e636146d"

source_dir=${SOURCE_DIR:-}
source_sha=${SOURCE_SHA:-}
log_path=${CSHARP_LOG:-/tmp/csharp-glibc-unit.log}
result_path=${CSHARP_RESULT:-/tmp/csharp-glibc-unit.json}

usage() {
  printf 'usage: csharp-gate.sh SOURCE_DIR SOURCE_SHA [LOG_PATH] [RESULT_PATH]\n' >&2
  printf '       csharp-gate.sh --source-dir DIR --source-sha SHA [--log PATH] [--result PATH]\n' >&2
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
    result_path=$1
    shift
  fi
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      source_dir=$2
      shift 2
      ;;
    --source-sha)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      source_sha=$2
      shift 2
      ;;
    --log)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      log_path=$2
      shift 2
      ;;
    --result)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      result_path=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'CSHARP_GATE_FAILURE: unknown argument: %s\n' "$1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$source_dir" || -z "$source_sha" ]]; then
  printf 'CSHARP_GATE_FAILURE: source directory and full source SHA are required\n' >&2
  usage
  exit 2
fi

if [[ ! "$source_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
  printf 'CSHARP_GATE_FAILURE: source SHA must be a full 40-character SHA\n' >&2
  exit 2
fi

if [[ ! "$source_dir" = /* ]]; then
  source_dir="$PWD/$source_dir"
fi
if [[ ! -d "$source_dir" ]]; then
  printf 'CSHARP_GATE_FAILURE: source directory does not exist: %s\n' "$source_dir" >&2
  exit 2
fi
source_dir=$(cd -- "$source_dir" && pwd -P)

log_parent=$(dirname -- "$log_path")
result_parent=$(dirname -- "$result_path")
if [[ ! -d "$log_parent" || ! -d "$result_parent" ]]; then
  printf 'CSHARP_GATE_FAILURE: log/result parent directory is missing\n' >&2
  exit 2
fi
if ! : > "$log_path"; then
  printf 'CSHARP_GATE_FAILURE: cannot create log: %s\n' "$log_path" >&2
  exit 2
fi

actual_source_sha=""
tests_executed=""
failure_step=""
failure_status=""
failure_detail=""

write_result() {
  local status=$1
  local step=$2
  local status_code=$3
  local detail=$4
  GATE_RESULT_STATUS="$status" \
  GATE_RESULT_STEP="$step" \
  GATE_RESULT_CODE="$status_code" \
  GATE_RESULT_DETAIL="$detail" \
  GATE_SOURCE_SHA="$source_sha" \
  GATE_ACTUAL_SOURCE_SHA="$actual_source_sha" \
  GATE_DOTNET_SDK="$EXPECTED_DOTNET_SDK" \
  GATE_ASMSTONE_COMMIT="$EXPECTED_ASMSTONE_COMMIT" \
  GATE_LLVM_COMMIT="$EXPECTED_LLVM_COMMIT" \
  GATE_CATALOG_SHA256="$EXPECTED_CATALOG_SHA256" \
  GATE_LICENSE_SHA256="$EXPECTED_ASMSTONE_LICENSE_SHA256" \
  GATE_TESTS_EXECUTED="$tests_executed" \
  GATE_LOG_PATH="$log_path" \
  python3 - "$result_path" <<'PY'
import json
import os
import sys


def optional_int(value):
    return int(value) if value.isdigit() else None


record = {
    "schema_version": 1,
    "status": os.environ["GATE_RESULT_STATUS"],
    "source_commit": os.environ["GATE_SOURCE_SHA"].lower(),
    "actual_source_commit": os.environ["GATE_ACTUAL_SOURCE_SHA"].lower(),
    "dotnet_sdk": os.environ["GATE_DOTNET_SDK"],
    "asmstone_commit": os.environ["GATE_ASMSTONE_COMMIT"],
    "llvm_commit": os.environ["GATE_LLVM_COMMIT"],
    "asmstone_catalog_sha256": os.environ["GATE_CATALOG_SHA256"],
    "asmstone_license_sha256": os.environ["GATE_LICENSE_SHA256"],
    "tests_executed": optional_int(os.environ["GATE_TESTS_EXECUTED"]),
    "log_path": os.environ["GATE_LOG_PATH"],
}
step = os.environ["GATE_RESULT_STEP"]
if step:
    record["failure_step"] = step
    record["failure_status"] = int(os.environ["GATE_RESULT_CODE"])
    record["failure_detail"] = os.environ["GATE_RESULT_DETAIL"]
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(record, output, indent=2, sort_keys=True)
    output.write("\n")
PY
}

fail_gate() {
  local code=$1
  local step=$2
  local detail=$3
  [[ "$code" -gt 0 ]] || code=1
  failure_step=$step
  failure_status=$code
  failure_detail=$detail
  printf 'CSHARP_GATE_FAILURE: step=%s status=%s detail=%s\n' \
    "$step" "$code" "$detail" | tee -a "$log_path" >&2
  write_result "fail" "$step" "$code" "$detail" || true
  exit "$code"
}

run_dotnet_step() {
  local step=$1
  shift
  printf '=== %s ===\n' "$step" | tee -a "$log_path"
  (cd -- "$dotnet_root" && DOTNET_MULTILEVEL_LOOKUP=0 "$dotnet_bin" "$@") 2>&1 \
    | tee -a "$log_path"
  local code=${PIPESTATUS[0]}
  if [[ "$code" -ne 0 ]]; then
    fail_gate "$code" "$step" "dotnet command failed"
  fi
}

verify_source_checkout() {
  printf '=== source provenance ===\n' | tee -a "$log_path"
  local source_git_dir="$source_dir/.git"
  if [[ ! -e "$source_git_dir" ]]; then
    fail_gate 1 source-provenance "private source is not a Git checkout"
  fi
  actual_source_sha=$(git -C "$source_dir" rev-parse HEAD 2>>"$log_path") || \
    fail_gate 1 source-provenance "unable to resolve detached source HEAD"
  actual_source_sha=${actual_source_sha,,}
  if [[ "$actual_source_sha" != "${source_sha,,}" ]]; then
    fail_gate 1 source-provenance \
      "checked out $actual_source_sha, expected ${source_sha,,}"
  fi
  printf 'SOURCE_SHA_OK: %s\n' "$actual_source_sha" | tee -a "$log_path"
}

verify_asmstone() {
  printf '=== AsmStone provenance ===\n' | tee -a "$log_path"
  local gitlink
  local submodule_head
  gitlink=$(git -C "$source_dir" ls-tree HEAD -- third_party/AsmStone \
    | awk '$NF == "third_party/AsmStone" { print $3; exit }') || \
    fail_gate 1 asmstone-gitlink "unable to inspect the AsmStone gitlink"
  if [[ "$gitlink" != "$EXPECTED_ASMSTONE_COMMIT" ]]; then
    fail_gate 1 asmstone-gitlink \
      "gitlink=$gitlink, expected $EXPECTED_ASMSTONE_COMMIT"
  fi
  submodule_head=$(git -C "$source_dir/third_party/AsmStone" rev-parse HEAD 2>>"$log_path") || \
    fail_gate 1 asmstone-submodule "unable to resolve the initialized AsmStone submodule"
  submodule_head=${submodule_head,,}
  if [[ "$submodule_head" != "$EXPECTED_ASMSTONE_COMMIT" ]]; then
    fail_gate 1 asmstone-submodule \
      "submodule=$submodule_head, expected $EXPECTED_ASMSTONE_COMMIT"
  fi
  printf 'ASMSTONE_COMMIT_OK: %s\n' "$submodule_head" | tee -a "$log_path"

  local lock_path="$source_dir/third_party/AsmStone/spec/source-lock.json"
  local catalog_path="$source_dir/third_party/AsmStone/src/AsmStone/Generated/A64GeneratedInstructionTable.cs"
  local license_path="$source_dir/third_party/AsmStone/LICENSE"
  [[ -f "$lock_path" ]] || fail_gate 1 catalog-provenance "missing AsmStone source-lock.json"
  [[ -f "$catalog_path" ]] || fail_gate 1 catalog-provenance "missing generated LLVM catalog"
  [[ -f "$license_path" ]] || fail_gate 1 license-provenance "missing AsmStone LICENSE"

  set +e
  catalog_output=$(python3 - "$lock_path" "$catalog_path" \
    "$license_path" "$EXPECTED_LLVM_COMMIT" "$EXPECTED_CATALOG_SHA256" \
    "$EXPECTED_ASMSTONE_LICENSE_SHA256" <<'PY'
import hashlib
import json
import pathlib
import sys


lock_path = pathlib.Path(sys.argv[1])
catalog_path = pathlib.Path(sys.argv[2])
license_path = pathlib.Path(sys.argv[3])
expected_llvm_commit = sys.argv[4]
expected_catalog_sha = sys.argv[5]
expected_license_sha = sys.argv[6]
try:
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    llvm = lock["sources"]["llvm"]
    actual_commit = llvm["commit"]
    actual_catalog_sha = llvm["tablegenJsonSha256"]
    generated_sha = llvm["generatedCatalogSha256"]
except (OSError, KeyError, TypeError, ValueError) as exc:
    print(f"malformed LLVM source lock: {exc}", file=sys.stderr)
    raise SystemExit(1)

if actual_commit != expected_llvm_commit:
    print(f"LLVM commit={actual_commit}, expected {expected_llvm_commit}", file=sys.stderr)
    raise SystemExit(1)
if actual_catalog_sha != expected_catalog_sha:
    print(f"catalog input SHA={actual_catalog_sha}, expected {expected_catalog_sha}", file=sys.stderr)
    raise SystemExit(1)

actual_generated_sha = hashlib.sha256(catalog_path.read_bytes()).hexdigest()
if actual_generated_sha != generated_sha:
    print(
        f"generated catalog SHA={actual_generated_sha}, source lock declares {generated_sha}",
        file=sys.stderr,
    )
    raise SystemExit(1)

actual_license_sha = hashlib.sha256(license_path.read_bytes()).hexdigest()
if actual_license_sha != expected_license_sha:
    print(
        f"AsmStone LICENSE SHA={actual_license_sha}, expected {expected_license_sha}",
        file=sys.stderr,
    )
    raise SystemExit(1)

catalog = catalog_path.read_text(encoding="utf-8")
if f"LLVM source commit: {expected_llvm_commit}" not in catalog:
    print("generated catalog LLVM commit comment does not match source lock", file=sys.stderr)
    raise SystemExit(1)
if f"TableGen JSON SHA-256: {expected_catalog_sha}" not in catalog:
    print("generated catalog input SHA comment does not match source lock", file=sys.stderr)
    raise SystemExit(1)

print(f"LLVM_COMMIT_OK: {actual_commit}")
print(f"LLVM_CATALOG_INPUT_SHA_OK: {actual_catalog_sha}")
print(f"LLVM_GENERATED_CATALOG_SHA_OK: {actual_generated_sha}")
print(f"ASMSTONE_LICENSE_SHA_OK: {actual_license_sha}")
PY
  )
  local catalog_code=$?
  set -u
  printf '%s\n' "$catalog_output" | tee -a "$log_path"
  if [[ "$catalog_code" -ne 0 ]]; then
    fail_gate "$catalog_code" catalog-provenance "LLVM catalog/source-lock verification failed"
  fi
}

verify_dotnet() {
  printf '=== SDK probe ===\n' | tee -a "$log_path"
  dotnet_bin=$(command -v dotnet || true)
  if [[ -z "$dotnet_bin" || ! -x "$dotnet_bin" ]]; then
    fail_gate 127 sdk-probe "dotnet executable is missing"
  fi
  set +e
  dotnet_version_output=$(cd -- "$dotnet_root" && DOTNET_MULTILEVEL_LOOKUP=0 \
    "$dotnet_bin" --version 2>&1)
  local version_code=$?
  set -u
  printf '%s\n' "$dotnet_version_output" | tee -a "$log_path"
  if [[ "$version_code" -ne 0 ]]; then
    fail_gate "$version_code" sdk-probe "dotnet --version failed"
  fi
  dotnet_version=$(printf '%s\n' "$dotnet_version_output" | tail -n 1 | tr -d '\r')
  if [[ "$dotnet_version" != "$EXPECTED_DOTNET_SDK" ]]; then
    fail_gate 1 sdk-probe \
      "effective SDK=$dotnet_version, expected $EXPECTED_DOTNET_SDK"
  fi
  printf 'DOTNET_SDK_OK: %s\n' "$dotnet_version" | tee -a "$log_path"
}

check_test_count() {
  local output_path=$1
  local trx_path=$2
  set +e
  test_summary=$(python3 - "$output_path" "$trx_path" <<'PY'
import pathlib
import re
import sys
import xml.etree.ElementTree as ET


output = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
trx_path = pathlib.Path(sys.argv[2])
totals = []
patterns = (
    r"Total\s+tests?\s*[:=]\s*(\d+)",
    r"Tests?\s+run\s*[:=]\s*(\d+)",
    r"Total:\s*(\d+)",
)
for pattern in patterns:
    totals.extend(int(value) for value in re.findall(pattern, output, flags=re.IGNORECASE))

if trx_path.is_file():
    try:
        root = ET.parse(trx_path).getroot()
        for element in root.iter():
            counters = element.attrib
            if "total" in counters and counters["total"].isdigit():
                totals.append(int(counters["total"]))
    except (OSError, ET.ParseError) as exc:
        print(f"malformed TRX result: {exc}", file=sys.stderr)
        raise SystemExit(1)

if not totals:
    print("unable to prove that dotnet test executed at least one test", file=sys.stderr)
    raise SystemExit(1)
test_count = max(totals)
if test_count == 0:
    print("zero tests were executed", file=sys.stderr)
    raise SystemExit(1)
print(f"TESTS_EXECUTED: {test_count}")
PY
  )
  local count_code=$?
  set -u
  printf '%s\n' "$test_summary" | tee -a "$log_path"
  if [[ "$count_code" -ne 0 ]]; then
    fail_gate "$count_code" test-selection "dotnet test did not prove a nonzero test count"
  fi
  tests_executed=$(printf '%s\n' "$test_summary" | sed -n 's/^TESTS_EXECUTED: //p' | tail -n 1)
  [[ "$tests_executed" =~ ^[1-9][0-9]*$ ]] || \
    fail_gate 1 test-selection "test count parser returned an invalid value"
}

verify_source_checkout
verify_asmstone

solution="$source_dir/cs/Vmp.sln"
[[ -f "$solution" ]] || fail_gate 1 source-provenance "missing C# solution: cs/Vmp.sln"

dotnet_root=$(mktemp -d "${TMPDIR:-/tmp}/csharp-dotnet.XXXXXX") || \
  fail_gate 1 sdk-probe "unable to create temporary SDK resolution directory"
trap 'rm -rf "$dotnet_root"' EXIT
cat > "$dotnet_root/global.json" <<EOF
{
  "sdk": {
    "version": "$EXPECTED_DOTNET_SDK",
    "rollForward": "disable",
    "allowPrerelease": false
  }
}
EOF
printf 'DOTNET_GLOBAL_JSON: %s\n' "$dotnet_root/global.json" | tee -a "$log_path"

verify_dotnet
run_dotnet_step dotnet-restore restore "$solution" --nologo
run_dotnet_step dotnet-build build "$solution" --configuration Release --no-restore --nologo

test_output="$dotnet_root/csharp-test-output.log"
trx_path="$source_dir/cs/TestResults/csharp-glibc-unit.trx"
mkdir -p "$(dirname -- "$trx_path")"
printf '=== dotnet-test ===\n' | tee -a "$log_path"
set +e
(cd -- "$dotnet_root" && DOTNET_MULTILEVEL_LOOKUP=0 "$dotnet_bin" test "$solution" \
  --configuration Release --no-build --no-restore \
  --logger 'trx;LogFileName=csharp-glibc-unit.trx' \
  --results-directory "$source_dir/cs/TestResults" --nologo) 2>&1 \
  | tee -a "$log_path" | tee "$test_output"
test_code=${PIPESTATUS[0]}
set -u
if [[ "$test_code" -ne 0 ]]; then
  fail_gate "$test_code" dotnet-test "dotnet test returned a nonzero status"
fi
check_test_count "$test_output" "$trx_path"

# Keep the replacement boundary explicit in CI instead of relying only on the
# aggregate solution test. These focused commands are the reproducibility
# probes for generated encoding, managed decoding, and NativeBlob policy.
run_dotnet_step asmstone-encoder-differential test \
  "$source_dir/cs/tests/Vmp.Arm64.Encoding.Tests/Vmp.Arm64.Encoding.Tests.csproj" \
  --configuration Release --no-build --no-restore --nologo \
  --filter FullyQualifiedName~AsmStoneGeneratedEncodingParityTests
run_dotnet_step asmstone-decoder-differential test \
  "$source_dir/cs/tests/Vmp.Lifter.Arm64.Tests/Vmp.Lifter.Arm64.Tests.csproj" \
  --configuration Release --no-build --no-restore --nologo \
  --filter FullyQualifiedName~AsmStoneArm64AdapterTests
run_dotnet_step native-blob-policy-differential test \
  "$source_dir/cs/tests/Vmp.Runtime.Native.Tests/Vmp.Runtime.Native.Tests.csproj" \
  --configuration Release --no-build --no-restore --nologo \
  --filter FullyQualifiedName~NativeBlobTests

printf 'CSHARP_GATE_OK: source=%s sdk=%s tests=%s\n' \
  "${source_sha,,}" "$EXPECTED_DOTNET_SDK" "$tests_executed" | tee -a "$log_path"
write_result "pass" "" 0 "" || \
  fail_gate 1 result "unable to write C# gate result"
