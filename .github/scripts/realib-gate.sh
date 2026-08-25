#!/usr/bin/env bash
set -u -o pipefail

log_path=${1:?usage: realib-gate.sh LOG_PATH}
suites=(tinylib sqlite libcrypto libz yamlcpp protobuflite cpp_business matrix)
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
  ratio=$(ratio_for "$suite")
  ratio=${ratio:-0.0}
  cargo_status=$(status_for "realib_${suite}")
  cargo_status=${cargo_status:-999}
  result=PASS

  if [[ "$cargo_status" -ne 0 ]]; then
    echo "${suite}: REALIB CARGO TEST FAIL: status=$cargo_status"
    gate_fail=1
    result=FAIL
  fi
  if ! awk "BEGIN {exit !($ratio >= 1.0)}"; then
    echo "${suite}: GATE FAIL: ratio=$ratio < 1.0"
    gate_fail=1
    result=FAIL
  fi

  printf '%-14s surviving_pass_ratio = %s cargo_status = %s %s\n' \
    "$suite" "$ratio" "$cargo_status" "$result"
  printf '| %s | %s | %s | %s |\n' "$suite" "$ratio" "$cargo_status" "$result" \
    >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
done

for label in e2e_eh_fixture; do
  cargo_status=$(status_for "$label")
  cargo_status=${cargo_status:-999}
  if [[ "$cargo_status" -ne 0 ]]; then
    echo "$label: E2E TEST FAIL: status=$cargo_status"
    gate_fail=1
  fi
done

if [[ "$gate_fail" -ne 0 ]]; then
  exit 1
fi
