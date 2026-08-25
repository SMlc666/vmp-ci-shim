#!/usr/bin/env bash
# Select independent E2E work for one runner. The fixture harness isolates
# realib runs, so the heavy suites can execute on separate machines safely.

set -euo pipefail

e2e_shard_plan() {
  local instances=${1:?missing shard count}
  local shard=${2:?missing shard index}
  E2E_TARGETS=()
  E2E_PAIRS=()
  E2E_SUITES=()

  case "${instances}:${shard}" in
    1:0)
      E2E_TARGETS=(
        eh_fixture_e2e realib_tinylib_e2e realib_sqlite_e2e
        realib_libcrypto_e2e realib_libz_e2e realib_yamlcpp_e2e
        realib_protobuflite_e2e realib_cpp_business_e2e realib_matrix_e2e
      )
      E2E_PAIRS=(
        eh_fixture_e2e e2e_eh_fixture
        realib_tinylib_e2e realib_tinylib
        realib_sqlite_e2e realib_sqlite
        realib_libcrypto_e2e realib_libcrypto
        realib_libz_e2e realib_libz
        realib_yamlcpp_e2e realib_yamlcpp
        realib_protobuflite_e2e realib_protobuflite
        realib_cpp_business_e2e realib_cpp_business
        realib_matrix_e2e realib_matrix
      )
      E2E_SUITES=(e2e_eh_fixture tinylib sqlite libcrypto libz yamlcpp protobuflite cpp_business matrix)
      ;;
    2:0)
      E2E_TARGETS=(
        eh_fixture_e2e realib_tinylib_e2e realib_sqlite_e2e
        realib_libcrypto_e2e realib_libz_e2e realib_cpp_business_e2e
      )
      E2E_PAIRS=(
        eh_fixture_e2e e2e_eh_fixture
        realib_tinylib_e2e realib_tinylib
        realib_sqlite_e2e realib_sqlite
        realib_libcrypto_e2e realib_libcrypto
        realib_libz_e2e realib_libz
        realib_cpp_business_e2e realib_cpp_business
      )
      E2E_SUITES=(e2e_eh_fixture tinylib sqlite libcrypto libz cpp_business)
      ;;
    2:1)
      E2E_TARGETS=(realib_yamlcpp_e2e realib_protobuflite_e2e realib_matrix_e2e)
      E2E_PAIRS=(
        realib_yamlcpp_e2e realib_yamlcpp
        realib_protobuflite_e2e realib_protobuflite
        realib_matrix_e2e realib_matrix
      )
      E2E_SUITES=(yamlcpp protobuflite matrix)
      ;;
    4:0)
      E2E_TARGETS=(eh_fixture_e2e realib_tinylib_e2e realib_sqlite_e2e realib_libcrypto_e2e realib_libz_e2e)
      E2E_PAIRS=(
        eh_fixture_e2e e2e_eh_fixture
        realib_tinylib_e2e realib_tinylib
        realib_sqlite_e2e realib_sqlite
        realib_libcrypto_e2e realib_libcrypto
        realib_libz_e2e realib_libz
      )
      E2E_SUITES=(e2e_eh_fixture tinylib sqlite libcrypto libz)
      ;;
    4:1)
      E2E_TARGETS=(realib_yamlcpp_e2e realib_protobuflite_e2e)
      E2E_PAIRS=(
        realib_yamlcpp_e2e realib_yamlcpp
        realib_protobuflite_e2e realib_protobuflite
      )
      E2E_SUITES=(yamlcpp protobuflite)
      ;;
    4:2)
      E2E_TARGETS=(realib_cpp_business_e2e)
      E2E_PAIRS=(realib_cpp_business_e2e realib_cpp_business)
      E2E_SUITES=(cpp_business)
      ;;
    4:3)
      E2E_TARGETS=(realib_matrix_e2e)
      E2E_PAIRS=(realib_matrix_e2e realib_matrix)
      E2E_SUITES=(matrix)
      ;;
    *)
      echo "E2E_SHARD_PLAN_FAILURE: unsupported instances=${instances} shard=${shard}" >&2
      return 2
      ;;
  esac
}
