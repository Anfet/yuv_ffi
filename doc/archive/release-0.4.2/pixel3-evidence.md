# Pixel 3 release evidence — preliminary

**Date:** 2026-09-28
**Source HEAD:** `e66751e` (`release/0.4.2`)
**State:** Partial. The requested release-mode integration test is blocked by Flutter Driver; profile checks below are additional evidence and do not replace it.

## Device and environment

- Device: Google Pixel 3 (`blueline`), Android 12
- Serial: `8B1X11QLW`
- ABI order: `arm64-v8a,armeabi-v7a,armeabi`
- ADB: `device`
- Screen: `mWakefulness=Awake`, display `ON`, `isKeyguardShowing=false`
- Thermal service: status `0`
- Host: Windows 10 x64
- Flutter: 3.44.9; Dart: 3.12.2

## Completed checks

Profile app-runtime smoke:

```text
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/native_app_runtime_smoke_test.dart -d 8B1X11QLW --no-pub
YUV-06 app-runtime smoke passed on android
All tests passed.
```

Profile native probe:

```text
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/probe_native_test.dart -d 8B1X11QLW --no-pub
Probe matrix passed: 1188 cases
All tests passed.
```

Release ABI packages were built:

- `example/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` — 23.6 MB; contains `lib/armeabi-v7a/libyuv_ffi.so` and no other ABI directory.
- `example/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` — 29.1 MB; contains `lib/arm64-v8a/libyuv_ffi.so` and no other ABI directory.
- `ro.product.cpu.abilist` confirms the Pixel 3 supports both ABIs.
- The arm64 release APK installed and opened `com.example.yuv_ffi_example/.MainActivity`; Android reported `Displayed` and `Fully drawn` with no `FATAL EXCEPTION`, `E/flutter`, or `UnsatisfiedLinkError` in the captured logcat window.

## Remaining gate

The planned command

```text
flutter drive --release --driver=test_driver/integration_test.dart --target=integration_test/native_app_runtime_smoke_test.dart -d 8B1X11QLW --no-pub
```

exits before building with:

```text
Flutter Driver (non-web) does not support running in release mode.
Use --profile mode for testing application performance.
```

The release APK launch check does not execute the integration assertions. RA-25 therefore remains incomplete until the release-mode test is replaced with a supported release smoke mechanism or the gate is changed to profile mode. RA-26 speed measurements are also pending.
