#include <jni.h>
#include <android/log.h>

#define TAG "NativeBridgeSmoke"

jint JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)vm;
    (void)reserved;
    __android_log_print(ANDROID_LOG_INFO, TAG, "JNI_OnLoad reached");
    return JNI_VERSION_1_6;
}
