#!/usr/bin/bash
set -u -o pipefail

log_path=${1:?usage: realib-gate.sh LOG_PATH}
if [[ $# -gt 1 ]]; then
  suites=("${@:2}")
else
  suites=(e2e_eh_fixture tinylib sqlite libcrypto libz yamlcpp protobuflite cpp_business matrix)
fi
gate_fail=0

if [[ ! -f "$log_path" ]]; then
  echo "INFRA_FAILURE: missing e2e log $log_path" >&2
  exit 2
fi

status_for() {
  local label=$1
  sed -n "s/.*\[$label\] cargo_status = \([0-9][0-9]*\).*/\1/p" "$log_path" | tail -1
}

ratio_for() {
  local suite=$1
  sed -n "s/.*\[realib_${suite}\] surviving_pass_ratio = \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p" "$log_path" | tail -1
}

printf 'Realib gate\n' >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
printf '| suite | ratio | cargo status | result |\n|---|---:|---:|---|\n' >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

for suite in "${suites[@]}"; do
  status_label="realib_${suite}"
  if [[ "$suite" == e2e_eh_fixture ]]; then
    status_label="$suite"
  fi
  cargo_status=$(status_for "$status_label")
  cargo_status=${cargo_status:-999}
  result=PASS

  if [[ "$cargo_status" -ne 0 ]]; then
    echo "${suite}: REALIB CARGO TEST FAIL: status=$cargo_status"
    gate_fail=1
    result=FAIL
  fi

  # Matrix tests emit ratios for their underlying fixture, not for a virtual
  # realib_matrix suite. Their cargo status is the authoritative gate.
  if [[ "$suite" == matrix || "$suite" == e2e_eh_fixture ]]; then
    ratio=N/A
  else
    ratio=$(ratio_for "$suite")
    ratio=${ratio:-0.0}
    if ! awk "BEGIN {exit !($ratio >= 1.0)}"; then
      echo "${suite}: GATE FAIL: ratio=$ratio < 1.0"
      gate_fail=1
      result=FAIL
    fi
  fi

  printf '%-14s surviving_pass_ratio = %s cargo_status = %s %s\n' \
    "$suite" "$ratio" "$cargo_status" "$result"
  printf '| %s | %s | %s | %s |\n' "$suite" "$ratio" "$cargo_status" "$result" \
    >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
done

if [[ "$gate_fail" -ne 0 ]]; then
  exit 1
fi
