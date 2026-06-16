#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SRC_DIR="$ROOT_DIR/native_bridge_smoke"
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

SDK_ROOT=$(find_sdk_root)
SDKMANAGER=$(find_sdkmanager)
ANDROID_JAR="$SDK_ROOT/platforms/$PLATFORM/android.jar"
NDK_ROOT="$SDK_ROOT/ndk/$NDK_VERSION"
CLANG="$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang"

export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"

yes | "$SDKMANAGER" --licenses >/dev/null
"$SDKMANAGER" --install \
    "platform-tools" \
    "platforms;$PLATFORM" \
    "build-tools;$BUILD_TOOLS_VERSION" \
    "ndk;$NDK_VERSION" >/dev/null

AAPT=$(find_tool aapt)
APKSIGNER=$(find_tool apksigner)
D8=$(find_tool d8)
ZIPALIGN=$(find_tool zipalign)

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

"$D8" \
    --lib "$ANDROID_JAR" \
    --output "$OUT_DIR/payload" \
    "$OUT_DIR/classes"

"$CLANG" \
    -shared \
    -fPIC \
    -o "$OUT_DIR/payload/lib/arm64-v8a/libbridge_smoke.so" \
    "$SRC_DIR/bridge_jni.c" \
    -I"$NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include" \
    -llog

"$AAPT" package \
    -f \
    -M "$SRC_DIR/AndroidManifest.xml" \
    -I "$ANDROID_JAR" \
    -F "$OUT_DIR/unsigned.apk"

(
    cd "$OUT_DIR/payload"
    "$AAPT" add ../unsigned.apk classes.dex lib/arm64-v8a/libbridge_smoke.so >/dev/null
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
