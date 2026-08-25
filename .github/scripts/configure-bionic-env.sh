#!/usr/bin/env bash
set -euo pipefail

: "${TERMUX_PREFIX:?TERMUX_PREFIX is required}"
: "${TERMUX_HOME:?TERMUX_HOME is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"

for tool in cargo rustc clang clang++ llvm-ar; do
  if [[ ! -x "$TERMUX_PREFIX/bin/$tool" ]]; then
    echo "TOOLCHAIN_FAILURE: missing executable $TERMUX_PREFIX/bin/$tool" >&2
    exit 1
  fi
done

mkdir -p "$TERMUX_HOME/target"
ln -sfn "$TERMUX_HOME/target" "$GITHUB_WORKSPACE/src/target"

cat >> "$GITHUB_ENV" <<EOF
PREFIX=$TERMUX_PREFIX
HOME=$TERMUX_HOME
PATH=$TERMUX_PREFIX/bin:/tmp/host-toolchain-cleanbin:$PATH
LD_LIBRARY_PATH=$TERMUX_PREFIX/lib
HTTPS_PROXY=http://127.0.0.1:3128
HTTP_PROXY=http://127.0.0.1:3128
CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=$TERMUX_PREFIX/bin/clang
CARGO_TARGET_AARCH64_LINUX_ANDROID_AR=$TERMUX_PREFIX/bin/llvm-ar
CARGO_TARGET_DIR=$TERMUX_HOME/target
CC=$TERMUX_PREFIX/bin/clang
CXX=$TERMUX_PREFIX/bin/clang++
EOF

echo "BIONIC_TOOLCHAIN_OK: $TERMUX_PREFIX/bin/cargo"
