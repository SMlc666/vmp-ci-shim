#!/usr/bin/env bash
set -euo pipefail

wrapper_dir=${1:-/tmp/host-toolchain-cleanbin}
rm -rf "$wrapper_dir"
mkdir -p "$wrapper_dir"

for tool in aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ gcc g++ cc c++ clang clang++; do
  if [[ -x "/usr/bin/$tool" ]]; then
    cat > "$wrapper_dir/$tool" <<'EOF'
#!/usr/bin/env bash
tool="$(basename "$0")"
unset LD_LIBRARY_PATH
exec "/usr/bin/$tool" "$@"
EOF
    chmod +x "$wrapper_dir/$tool"
  fi
done

ls -la "$wrapper_dir"
