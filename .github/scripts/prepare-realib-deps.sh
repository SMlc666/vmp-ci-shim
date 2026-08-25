#!/usr/bin/bash
set -euo pipefail

libc=${REALIB_LIBC:?REALIB_LIBC must be glibc or bionic}
if [[ "$libc" == bionic ]]; then
  export TERMUX_PREFIX="${TERMUX_PREFIX:?TERMUX_PREFIX is required for bionic dependency setup}"
  export HOME="${TERMUX_HOME:?TERMUX_HOME is required for bionic dependency setup}"
  export PATH="$TERMUX_PREFIX/bin:/tmp/host-toolchain-cleanbin:$PATH"
  export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib"
  export HTTPS_PROXY="${HTTPS_PROXY:-http://127.0.0.1:3128}"
  export HTTP_PROXY="${HTTP_PROXY:-http://127.0.0.1:3128}"
fi

fetch_tarball() {
  local out=$1
  shift
  rm -f "$out"
  for url in "$@"; do
    echo "Fetching $url"
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 "$url" -o "$out" \
      && tar tzf "$out" >/dev/null; then
      return 0
    fi
    rm -f "$out"
  done
  echo "DEPENDENCY_FETCH_FAILURE: unable to fetch a valid tarball for $out" >&2
  return 1
}

if [[ "$libc" == glibc ]]; then
  if [[ ! -f /tmp/sqlite-amalgamation-3450300/sqlite3.c ]]; then
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 \
      https://sqlite.org/2024/sqlite-amalgamation-3450300.zip -o /tmp/sqlite.zip
    rm -rf /tmp/sqlite-amalgamation-3450300
    unzip -q /tmp/sqlite.zip -d /tmp
  fi

  if [[ ! -f /tmp/openssl-1.1.1w/libcrypto.so.1.1 ]]; then
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 \
      https://www.openssl.org/source/openssl-1.1.1w.tar.gz | tar xz -C /tmp
    (
      cd /tmp/openssl-1.1.1w
      ./config shared --prefix=/tmp/openssl-install
      make -j"$(nproc)"
      make install_sw
    )
    cp /tmp/openssl-install/lib/libcrypto.so* /tmp/openssl-1.1.1w/
  fi
elif [[ "$libc" == bionic ]]; then
  : "${TERMUX_PREFIX:?TERMUX_PREFIX is required for bionic dependency setup}"
  if [[ ! -f /tmp/sqlite-amalgamation-3450300/sqlite3.c ]]; then
    baked="$TERMUX_PREFIX/realib-sqlite/sqlite-amalgamation-3450300"
    if [[ -f "$baked/sqlite3.c" ]]; then
      rm -rf /tmp/sqlite-amalgamation-3450300
      cp -a "$baked" /tmp/sqlite-amalgamation-3450300
    else
      curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 \
        https://sqlite.org/2024/sqlite-amalgamation-3450300.zip -o /tmp/sqlite.zip
      rm -rf /tmp/sqlite-amalgamation-3450300
      unzip -q /tmp/sqlite.zip -d /tmp
    fi
  fi

  if [[ ! -f /tmp/openssl-1.1.1w/libcrypto.so.1.1 ]]; then
    baked="$TERMUX_PREFIX/realib-openssl/openssl-1.1.1w"
    if [[ ! -f "$baked/libcrypto.so.1.1" ]]; then
      echo "DEPENDENCY_FETCH_FAILURE: no bionic OpenSSL fixture in cache or image" >&2
      exit 1
    fi
    rm -rf /tmp/openssl-1.1.1w
    cp -a "$baked" /tmp/openssl-1.1.1w
  fi
else
  echo "DEPENDENCY_FETCH_FAILURE: unknown REALIB_LIBC=$libc" >&2
  exit 2
fi

if [[ ! -f /tmp/zlib-1.3.1/zlib.h ]]; then
  rm -rf /tmp/zlib-1.3.1
  mkdir -p /tmp/zlib-1.3.1
  fetch_tarball /tmp/zlib-1.3.1.tar.gz \
    https://zlib.net/zlib-1.3.1.tar.gz \
    https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
  tar xzf /tmp/zlib-1.3.1.tar.gz -C /tmp/zlib-1.3.1 --strip-components=1
fi

if [[ ! -f /tmp/yaml-cpp-0.9.0/include/yaml-cpp/yaml.h ]]; then
  rm -rf /tmp/yaml-cpp-0.9.0
  mkdir -p /tmp/yaml-cpp-0.9.0
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 \
    https://github.com/jbeder/yaml-cpp/archive/refs/tags/yaml-cpp-0.9.0.tar.gz -o /tmp/yamlcpp.tar.gz
  tar xzf /tmp/yamlcpp.tar.gz -C /tmp/yaml-cpp-0.9.0 --strip-components=1
fi

if [[ ! -f /tmp/protobuf-31.1/src/google/protobuf/message_lite.h ]]; then
  rm -rf /tmp/protobuf-31.1
  mkdir -p /tmp/protobuf-31.1
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 \
    https://github.com/protocolbuffers/protobuf/archive/refs/tags/v31.1.tar.gz -o /tmp/protobuf-v31.1.tar.gz
  tar xzf /tmp/protobuf-v31.1.tar.gz -C /tmp/protobuf-31.1 --strip-components=1
fi

cat >> "${GITHUB_ENV:?GITHUB_ENV is required}" <<EOF
SQLITE_SRC_DIR=/tmp/sqlite-amalgamation-3450300
OPENSSL_DIR=/tmp/openssl-1.1.1w
ZLIB_SRC_DIR=/tmp/zlib-1.3.1
YAMLCPP_SRC_DIR=/tmp/yaml-cpp-0.9.0
PROTOBUF_SRC_DIR=/tmp/protobuf-31.1
EOF

echo "REALIB_DEPS_OK: libc=$libc"
