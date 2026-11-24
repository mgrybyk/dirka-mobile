#include <jni.h>
#include <stdint.h>
#include <string.h>

#include "dirka_engine.h"

JNIEXPORT jlong JNICALL
Java_com_mgrybyk_dirka_TunnelNative_start(JNIEnv *env, jobject instance, jbyteArray input) {
    (void)instance;
    uint8_t bytes[4096];
    jsize length = (*env)->GetArrayLength(env, input);
    if (length <= 0 || (size_t)length > sizeof(bytes)) return 0;

    (*env)->GetByteArrayRegion(env, input, 0, length, (jbyte *)bytes);
    if ((*env)->ExceptionCheck(env)) return 0;
    dirka_client *client = dirka_client_start(bytes, (size_t)length);
    // Clear the copied configuration before returning.
    volatile uint8_t *clear = bytes;
    for (jsize i = 0; i < length; ++i) clear[i] = 0;
    return (jlong)(intptr_t)client;
}

JNIEXPORT jbyteArray JNICALL
Java_com_mgrybyk_dirka_TunnelNative_snapshot(JNIEnv *env, jobject instance, jlong handle) {
    (void)instance;
    uint8_t bytes[8192];
    int32_t length = dirka_client_snapshot((dirka_client *)(intptr_t)handle, bytes, sizeof(bytes));
    if (length <= 0 || (size_t)length > sizeof(bytes)) return NULL;

    jbyteArray output = (*env)->NewByteArray(env, length);
    if (output != NULL) (*env)->SetByteArrayRegion(env, output, 0, length, (const jbyte *)bytes);
    return output;
}

JNIEXPORT void JNICALL
Java_com_mgrybyk_dirka_TunnelNative_stop(JNIEnv *env, jobject instance, jlong handle) {
    (void)env;
    (void)instance;
    dirka_client_stop((dirka_client *)(intptr_t)handle);
}

JNIEXPORT void JNICALL
Java_com_mgrybyk_dirka_TunnelNative_destroy(JNIEnv *env, jobject instance, jlong handle) {
    (void)env;
    (void)instance;
    dirka_client_destroy((dirka_client *)(intptr_t)handle);
}

JNIEXPORT void JNICALL
Java_com_mgrybyk_dirka_TunnelNative_networkAvailable(JNIEnv *env, jobject instance, jlong handle) {
    (void)env;
    (void)instance;
    dirka_client_network_available((dirka_client *)(intptr_t)handle);
}
