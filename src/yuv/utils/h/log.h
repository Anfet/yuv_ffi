#ifndef YUV_LOG_H
#define YUV_LOG_H

#if defined(__ANDROID__)
#include <android/log.h>
#ifndef LOG_TAG
#define LOG_TAG "YUV_FFI"
#endif
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else

#include <stdio.h>

#define LOGI(...) printf("[INFO] " __VA_ARGS__); printf("\n")
#define debug(...) printf("[DEBUG] " __VA_ARGS__); printf("\n")
#define warn(...) printf("[WARN] " __VA_ARGS__); printf("\n")
#define error(...) printf("[ERROR] " __VA_ARGS__); printf("\n")
#endif

#endif // YUV_LOG_H
