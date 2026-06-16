#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SRC_DIR="$ROOT_DIR/native_bridge_smoke"
PRIVATE_SRC_DIR="${PRIVATE_SRC_DIR:-src}"
CPP_BUSINESS_DIR="$PRIVATE_SRC_DIR/tests/realib_fixtures/cpp_business"
CPP_BUSINESS_ANDROID_DIR="$CPP_BUSINESS_DIR/build/android/arm64-v8a"
OUT_DIR="${1:-native-bridge-smoke-build}"
APK_OUT="${2:-native-bridge-smoke.apk}"
PACKAGE_NAME="com.smlc666.nativebridgesmoke"
BUILD_TOOLS_VERSION="35.0.0"
NDK_VERSION="27.2.12479018"
PLATFORM="android-35"

find_sdk_root() {
    for candidate in \
        "${ANDROID_SDK_ROOT:-}" \
        "${ANDROID_HOME:-}" \
        "/usr/local/lib/android/sdk" \
        "$HOME/Android/Sdk"
    do
        if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

find_sdkmanager() {
    for candidate in \
        "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
        "$SDK_ROOT/cmdline-tools/bin/sdkmanager" \
        "$SDK_ROOT/tools/bin/sdkmanager"
    do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    command -v sdkmanager
}

find_tool() {
    tool="$1"
    candidate="$SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION/$tool"
    if [ -x "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    command -v "$tool"
}

require_file() {
    file_path="$1"
    if [ ! -f "$file_path" ]; then
        printf '[native-bridge-harness] ERROR: missing required file: %s\n' "$file_path" >&2
        exit 1
    fi
}

ensure_sdk_component() {
    marker="$1"
    shift
    if [ -e "$marker" ]; then
        return 0
    fi
    if [ -z "${SDKMANAGER:-}" ]; then
        printf '[native-bridge-harness] ERROR: sdkmanager unavailable and missing %s\n' "$marker" >&2
        exit 1
    fi
    yes | "$SDKMANAGER" --licenses >/dev/null
    "$SDKMANAGER" --install "$@" >/dev/null
}

SDK_ROOT=$(find_sdk_root)
SDKMANAGER=$(find_sdkmanager)
ANDROID_JAR="$SDK_ROOT/platforms/$PLATFORM/android.jar"
NDK_ROOT="$SDK_ROOT/ndk/$NDK_VERSION"
ANDROID_STL="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so"

export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_NDK_HOME="$NDK_ROOT"

ensure_sdk_component "$ANDROID_JAR" "platforms;$PLATFORM"
ensure_sdk_component "$SDK_ROOT/build-tools/$BUILD_TOOLS_VERSION/aapt" "build-tools;$BUILD_TOOLS_VERSION"
ensure_sdk_component "$NDK_ROOT" "ndk;$NDK_VERSION"

AAPT=$(find_tool aapt)
APKSIGNER=$(find_tool apksigner)
D8=$(find_tool d8)
ZIPALIGN=$(find_tool zipalign)

if [ ! -d "$CPP_BUSINESS_DIR" ]; then
    printf '[native-bridge-harness] ERROR: private cpp_business fixture not found at %s\n' "$CPP_BUSINESS_DIR" >&2
    exit 1
fi

bash "$CPP_BUSINESS_DIR/build.sh" --android-arm64
require_file "$CPP_BUSINESS_ANDROID_DIR/libcpp_business.so"
require_file "$CPP_BUSINESS_ANDROID_DIR/libcpp_business_jni.so"
require_file "$ANDROID_STL"

rm -rf "$OUT_DIR"
mkdir -p \
    "$OUT_DIR/classes" \
    "$OUT_DIR/payload/lib/arm64-v8a"

javac \
    -source 8 \
    -target 8 \
    -classpath "$ANDROID_JAR" \
    -d "$OUT_DIR/classes" \
    "$SRC_DIR/MainActivity.java"

jar cf "$OUT_DIR/classes.jar" -C "$OUT_DIR/classes" .

"$D8" \
    --lib "$ANDROID_JAR" \
    --output "$OUT_DIR/payload" \
    "$OUT_DIR/classes.jar"

cp "$CPP_BUSINESS_ANDROID_DIR/libcpp_business.so" \
   "$OUT_DIR/payload/lib/arm64-v8a/libcpp_business.so"
cp "$CPP_BUSINESS_ANDROID_DIR/libcpp_business_jni.so" \
   "$OUT_DIR/payload/lib/arm64-v8a/libcpp_business_jni.so"
cp "$ANDROID_STL" \
   "$OUT_DIR/payload/lib/arm64-v8a/libc++_shared.so"

"$AAPT" package \
    -f \
    -M "$SRC_DIR/AndroidManifest.xml" \
    -I "$ANDROID_JAR" \
    -F "$OUT_DIR/unsigned.apk"

(
    cd "$OUT_DIR/payload"
    "$AAPT" add \
        ../unsigned.apk \
        classes.dex \
        lib/arm64-v8a/libc++_shared.so \
        lib/arm64-v8a/libcpp_business.so \
        lib/arm64-v8a/libcpp_business_jni.so >/dev/null
)

keytool \
    -genkeypair \
    -alias androiddebugkey \
    -dname "CN=Android Debug,O=Android,C=US" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -storepass android \
    -keypass android \
    -keystore "$OUT_DIR/debug.keystore" >/dev/null 2>&1

"$ZIPALIGN" -f 4 "$OUT_DIR/unsigned.apk" "$OUT_DIR/aligned.apk"
"$APKSIGNER" sign \
    --ks "$OUT_DIR/debug.keystore" \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out "$APK_OUT" \
    "$OUT_DIR/aligned.apk" >/dev/null

printf 'Built %s for %s\n' "$APK_OUT" "$PACKAGE_NAME"
