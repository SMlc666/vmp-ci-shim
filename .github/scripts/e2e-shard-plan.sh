#!/usr/bin/env bash
# Select independent E2E work for one runner. The fixture harness isolates
# realib runs, so heavy suites can execute on separate machines safely.

set -euo pipefail

e2e_shard_plan() {
  local instances=${1:?missing shard count}
  local shard=${2:?missing shard index}
  E2E_TARGETS=()
  # Records are: test target, gate label, optional test-harness filter.
  E2E_RUNS=()
  E2E_SUITES=()

  case "${instances}:${shard}" in
    1:0)
      E2E_TARGETS=(
        eh_fixture_e2e realib_tinylib_e2e realib_sqlite_e2e
        realib_libcrypto_e2e realib_libz_e2e realib_yamlcpp_e2e
        realib_protobuflite_e2e realib_cpp_business_e2e realib_matrix_e2e
      )
      E2E_RUNS=(
        eh_fixture_e2e e2e_eh_fixture -
        realib_tinylib_e2e realib_tinylib -
        realib_sqlite_e2e realib_sqlite -
        realib_libcrypto_e2e realib_libcrypto -
        realib_libz_e2e realib_libz -
        realib_yamlcpp_e2e realib_yamlcpp -
        realib_protobuflite_e2e realib_protobuflite -
        realib_cpp_business_e2e realib_cpp_business -
        realib_matrix_e2e realib_matrix -
      )
      E2E_SUITES=(e2e_eh_fixture tinylib sqlite libcrypto libz yamlcpp protobuflite cpp_business matrix)
      ;;
    2:0)
      E2E_TARGETS=(
        eh_fixture_e2e realib_tinylib_e2e realib_sqlite_e2e
        realib_libcrypto_e2e realib_libz_e2e realib_cpp_business_e2e
      )
      E2E_RUNS=(
        eh_fixture_e2e e2e_eh_fixture -
        realib_tinylib_e2e realib_tinylib -
        realib_sqlite_e2e realib_sqlite -
        realib_libcrypto_e2e realib_libcrypto -
        realib_libz_e2e realib_libz -
        realib_cpp_business_e2e realib_cpp_business realib_common::
        realib_cpp_business_e2e realib_cpp_business cpp_business_fixture_
        realib_cpp_business_e2e realib_cpp_business cpp_business_build_script
        realib_cpp_business_e2e realib_cpp_business cpp_business_android_build_mode
        realib_cpp_business_e2e realib_cpp_business cpp_business_mega_case
        realib_cpp_business_e2e realib_cpp_business cpp_business_policy_profiles
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_protected_no_regressions
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_policy_v6_no_regressions
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_policy_k1_no_regressions
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_policy_native_no_regressions
      )
      E2E_SUITES=(e2e_eh_fixture tinylib sqlite libcrypto libz cpp_business)
      ;;
    2:1)
      E2E_TARGETS=(realib_yamlcpp_e2e realib_protobuflite_e2e realib_matrix_e2e realib_cpp_business_e2e)
      E2E_RUNS=(
        realib_yamlcpp_e2e realib_yamlcpp -
        realib_protobuflite_e2e realib_protobuflite -
        realib_matrix_e2e realib_matrix -
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_policy_ultra_no_regressions
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_phase2_waterfall_ultra
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_policy_v6_v18_1_public
        realib_cpp_business_e2e realib_cpp_business cpp_business_v6_public_strip_tools_preserve_runtime
        realib_cpp_business_e2e realib_cpp_business cpp_business_v18_1_entry_signature_scan
        realib_cpp_business_e2e realib_cpp_business cpp_business_v6_policy_public_protect
      )
      E2E_SUITES=(yamlcpp protobuflite matrix cpp_business)
      ;;
    4:0)
      E2E_TARGETS=(eh_fixture_e2e realib_tinylib_e2e realib_sqlite_e2e realib_libcrypto_e2e realib_libz_e2e)
      E2E_RUNS=(
        eh_fixture_e2e e2e_eh_fixture -
        realib_tinylib_e2e realib_tinylib -
        realib_sqlite_e2e realib_sqlite -
        realib_libcrypto_e2e realib_libcrypto -
        realib_libz_e2e realib_libz -
      )
      E2E_SUITES=(e2e_eh_fixture tinylib sqlite libcrypto libz)
      ;;
    4:1)
      E2E_TARGETS=(realib_yamlcpp_e2e realib_protobuflite_e2e realib_matrix_e2e)
      E2E_RUNS=(
        realib_yamlcpp_e2e realib_yamlcpp -
        realib_protobuflite_e2e realib_protobuflite -
        realib_matrix_e2e realib_matrix -
      )
      E2E_SUITES=(yamlcpp protobuflite matrix)
      ;;
    4:2)
      E2E_TARGETS=(realib_cpp_business_e2e)
      E2E_RUNS=(
        realib_cpp_business_e2e realib_cpp_business realib_common::
        realib_cpp_business_e2e realib_cpp_business cpp_business_fixture_
        realib_cpp_business_e2e realib_cpp_business cpp_business_build_script
        realib_cpp_business_e2e realib_cpp_business cpp_business_android_build_mode
        realib_cpp_business_e2e realib_cpp_business cpp_business_mega_case
        realib_cpp_business_e2e realib_cpp_business cpp_business_policy_profiles
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_protected_no_regressions
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_policy_v6_no_regressions
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_policy_k1_no_regressions
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_policy_native_no_regressions
      )
      E2E_SUITES=(cpp_business)
      ;;
    4:3)
      E2E_TARGETS=(realib_cpp_business_e2e)
      E2E_RUNS=(
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_policy_ultra_no_regressions
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_phase2_waterfall_ultra
        realib_cpp_business_e2e realib_cpp_business cpp_business_suite_policy_v6_v18_1_public
        realib_cpp_business_e2e realib_cpp_business cpp_business_v6_public_strip_tools_preserve_runtime
        realib_cpp_business_e2e realib_cpp_business cpp_business_v18_1_entry_signature_scan
        realib_cpp_business_e2e realib_cpp_business cpp_business_v6_policy_public_protect
      )
      E2E_SUITES=(cpp_business)
      ;;
    *)
      echo "E2E_SHARD_PLAN_FAILURE: unsupported instances=${instances} shard=${shard}" >&2
      return 2
      ;;
  esac
}
