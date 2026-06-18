# syntax=docker/dockerfile:1
#
# Pre-baked termux/bionic environment with rust + git installed.
# Consumed by vmp-ci-shim's private_bionic CI job.
#
# Build via .github/workflows/build-bionic-image.yml — that workflow
# starts tinyproxy on the build host and `docker build --network host`,
# so apt inside the container reaches the proxy at 127.0.0.1:3128
# (bionic resolver is broken; proxy provides DNS via host glibc).

FROM termux/termux-docker:aarch64

ARG BUILD_PROXY=http://127.0.0.1:3128/

USER 1000

RUN PREFIX=/data/data/com.termux/files/usr && \
    mkdir -p "$PREFIX/etc/apt/apt.conf.d" && \
    printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' "$BUILD_PROXY" "$BUILD_PROXY" \
      > "$PREFIX/etc/apt/apt.conf.d/99proxy-build" && \
    mkdir -p /data/data/com.termux/cache/apt/archives/partial && \
    mkdir -p /data/data/com.termux/cache/apt/lists/partial && \
    "$PREFIX/bin/apt" update -y && \
    "$PREFIX/bin/apt" install -y rust git tcl curl unzip perl make clang cmake tar && \
    mkdir -p "$PREFIX/realib-sqlite" && cd "$PREFIX/realib-sqlite" && \
    "$PREFIX/bin/curl" -fSL -x "$BUILD_PROXY" -o amalg.zip \
      "https://www.sqlite.org/2024/sqlite-amalgamation-3450300.zip" && \
    "$PREFIX/bin/curl" -fSL -x "$BUILD_PROXY" -o src.zip \
      "https://www.sqlite.org/2024/sqlite-src-3450300.zip" && \
    "$PREFIX/bin/unzip" -oq amalg.zip && "$PREFIX/bin/unzip" -oq src.zip && \
    rm -f amalg.zip src.zip && \
    clang -shared -fPIC -O2 \
      -o "$PREFIX/realib-sqlite/sqlite-amalgamation-3450300/libsqlite3.so" \
      "$PREFIX/realib-sqlite/sqlite-amalgamation-3450300/sqlite3.c" && \
    mkdir -p "$PREFIX/realib-openssl" && cd "$PREFIX/realib-openssl" && \
    "$PREFIX/bin/curl" -fSL -x "$BUILD_PROXY" -o openssl.tar.gz \
      "https://www.openssl.org/source/openssl-1.1.1w.tar.gz" && \
    tar xzf openssl.tar.gz && rm -f openssl.tar.gz && \
    cd openssl-1.1.1w && \
    CC=clang "$PREFIX/bin/perl" ./Configure linux-aarch64 shared no-asm no-tests && \
    make -j4 build_libs && \
    rm "$PREFIX/etc/apt/apt.conf.d/99proxy-build" && \
    "$PREFIX/bin/rustc" --version && \
    "$PREFIX/bin/git" --version && \
    ls -l "$PREFIX/bin/tclsh" && \
    ls -l "$PREFIX/realib-sqlite/sqlite-amalgamation-3450300/sqlite3.c" && \
    ls -l "$PREFIX/realib-sqlite/sqlite-amalgamation-3450300/libsqlite3.so" && \
    ls -d "$PREFIX/realib-sqlite/sqlite-src-3450300" && \
    ls -l "$PREFIX/realib-openssl/openssl-1.1.1w/libcrypto.so"* && \
    ls -l "$PREFIX/realib-openssl/openssl-1.1.1w/include/openssl/sha.h"
