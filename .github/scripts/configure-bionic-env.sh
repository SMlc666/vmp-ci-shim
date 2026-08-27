#!/usr/bin/bash
set -euo pipefail

: "${TERMUX_PREFIX:?TERMUX_PREFIX is required}"
: "${TERMUX_HOME:?TERMUX_HOME is required}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"

for tool in cargo rustc clang clang++ llvm-ar llvm-readobj llvm-strip; do
  if [[ ! -x "$TERMUX_PREFIX/bin/$tool" ]]; then
    echo "TOOLCHAIN_FAILURE: missing executable $TERMUX_PREFIX/bin/$tool" >&2
    exit 1
  fi
done

mkdir -p "$TERMUX_HOME/target"
ln -sfn "$TERMUX_HOME/target" "$GITHUB_WORKSPACE/src/target"

echo "BIONIC_TOOLCHAIN_OK: $TERMUX_PREFIX/bin/cargo"
