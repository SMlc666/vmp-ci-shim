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
    "$PREFIX/bin/apt" install -y rust git && \
    rm "$PREFIX/etc/apt/apt.conf.d/99proxy-build" && \
    "$PREFIX/bin/rustc" --version && \
    "$PREFIX/bin/git" --version
