#!/usr/bin/bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "E2E_BUILD_FAILURE: no test targets supplied" >&2
  exit 2
fi

cargo_args=(-p vmp-lifter)
for target in "$@"; do
  cargo_args+=(--test "$target")
done
cargo_args+=(--no-run --quiet)

# The integration tests invoke the protector binary directly. Build it from
# this checkout instead of relying on a stale target-cache executable.
if [[ "${BIONIC_MODE:-0}" == "1" ]]; then
  : "${BIONIC_PREFIX:?BIONIC_PREFIX is required}"
  : "${BIONIC_HOME:?BIONIC_HOME is required}"
  env \
    HOME="$BIONIC_HOME" \
    PATH="$BIONIC_PREFIX/bin:/tmp/host-toolchain-cleanbin:${PATH}" \
    LD_LIBRARY_PATH="$BIONIC_PREFIX/lib" \
    CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$BIONIC_HOME/target}" \
    CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$BIONIC_PREFIX/bin/clang" \
    CARGO_TARGET_AARCH64_LINUX_ANDROID_AR="$BIONIC_PREFIX/bin/llvm-ar" \
    "$BIONIC_PREFIX/bin/cargo" build -p vmp-lifter --bin vmp-lifter --quiet
    "$BIONIC_PREFIX/bin/cargo" test "${cargo_args[@]}"
else
  cargo build -p vmp-lifter --bin vmp-lifter --quiet
  cargo test "${cargo_args[@]}"
fi

echo "E2E_BUILD_OK: ${#@} targets"
