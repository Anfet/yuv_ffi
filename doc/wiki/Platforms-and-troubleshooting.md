# Platforms and troubleshooting

**Task:** initialize `yuv_ffi` correctly (once in every isolate), know which platforms and modes are verified, and fix
the errors you are most likely to meet when loading the native library or the Web module.

**Conditions:** a Flutter app that already depends on `yuv_ffi` (see
[Getting started](https://github.com/Anfet/yuv_ffi/wiki/Getting-started)).

## Initialize in every isolate

`YuvFfi.initialize()` prepares the backend and returns the `YuvCapabilities` of what it loaded.

- On Web it must be awaited before any `YuvImage` operation: there is no lazy fallback.
- On native platforms it must finish before the capability-gated calls (`applyRgbaBytes`, the effects, blurs, crop,
  flips, rotation, `applyFormat`, `applyChromaSwap`, `cropped`, `rotated`, `toI420`, `toNv12`, `toBgra`). Constructors,
  plane access, `copy`, `applyPlanes`, the byte getters, encoding and decoding keep working without it.
- A successful initialization is cached, and concurrent callers on Web share one attempt. A failed attempt is not
  cached: the next call tries again, so a transient failure can recover without restarting the app.
- The state is per isolate. A new isolate starts uninitialized and must call `initialize()` itself.

The last point matters when you move work off the UI isolate. Send plain bytes and sizes, initialize inside the isolate,
rebuild the image there and send bytes back:

```dart
import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

typedef BlurJob = ({Uint8List bgra, int width, int height});

/// Runs in a background isolate, which starts uninitialized.
Future<Uint8List> blurBgra(BlurJob job) async {
  await YuvFfi.initialize();
  final image = YuvImage.bgra(job.width, job.height);
  image.yPlane.assignFrom(job.bgra);
  image.markDirty();
  image.applyGaussianBlur(radius: 5, sigma: 3);
  return image.toBgraBytes();
}

/// Blurs [image] without blocking the UI isolate and returns tight BGRA bytes.
Future<Uint8List> blurOffTheUiIsolate(YuvImage image) {
  return compute(blurBgra, (bgra: image.toBgraBytes(), width: image.width, height: image.height));
}
```

Expected result: the call completes with `width * height * 4` bytes of the blurred image, and the UI keeps painting
while it runs. `assignFrom` needs a buffer of exactly the plane's length; `toBgraBytes()` of a tight BGRA image is exactly
that. Do the same in any isolate you start yourself.

## Platforms

The README keeps the authoritative requirement and platform status tables
([Requirements](https://github.com/Anfet/yuv_ffi#requirements) and
[Platform status](https://github.com/Anfet/yuv_ffi#platform-status)). In short:

| Platform | What to know |
| --- | --- |
| Android | API 26 or later; ABIs `armeabi-v7a`, `arm64-v8a` and `x86_64`. Android `x86` is not supported. |
| iOS, macOS | Built into the app with Swift Package Manager or CocoaPods using the Flutter template's `use_frameworks!` (dynamic frameworks); nothing to add in those setups. The native symbols are linked into the process. Static CocoaPods linkage (for example `use_frameworks! :linkage => :static`, or no `use_frameworks!`) has not been verified and is not claimed. |
| Windows, Linux | Native FFI backend, built from `src/` with the app; the loader opens `yuv_ffi.dll` or `libyuv_ffi.so` by name. |
| Web | WASM backend on Flutter's JavaScript and `--wasm` builds, checked in Chrome. See below. |

The maintainer's checks for every platform run from scripts in the repository; the results are recorded per release and
the README lists what each platform was checked with. Anything not listed there is not a claim.

### Web

- Build with `flutter build web` or `flutter build web --wasm`. Both were verified in Chrome; Safari and Firefox have not
  been verified. Safari 16.4 is only a technical minimum for release WASM SIMD, not a tested compatibility claim.
- Await `YuvFfi.initialize()` before anything else. The module is requested from the app's own assets at
  `assets/packages/yuv_ffi/assets/wasm/yuv_ffi.js` and `.../yuv_ffi.wasm`.
  The paths are relative, so the browser resolves them against the page's base URL, as in the output of a plain
  `flutter build web`. `initialize()` takes no path argument. A custom `assetBase`, a CDN or a different origin, and a
  strict Content-Security-Policy have not been verified and are not claimed.
- The loaded module defines the capabilities. Use `capabilities.supports(...)` to choose a path; `chromaSwap` is
  supported for NV12 only, as on native.
- The checked cases and the evidence are in the
  [Web parity evidence](https://github.com/Anfet/yuv_ffi/blob/main/doc/web-parity.md).

### Tests of your own code

`flutter test` runs on a plain Dart VM, where the app's bundled native library does not exist. A test that calls a
processing method needs the library built from the repository's `src/` and placed on the loader's library path (the
package's `tool/ci/vm.ps1` shows how on Windows). Tests that only create images and read planes do not need it.

## Troubleshooting

### `UnsupportedError`: `YuvFfi.initialize() must complete before ...`

- Symptom: a processing call throws as soon as it runs, in a new screen, a test or a background isolate.
- Check: was `await YuvFfi.initialize()` executed, to completion, in the isolate that makes the call?
- Action: initialize at startup in the main isolate and again at the start of every isolate you create. The message
  says the capability has not been determined yet; it does not mean the operation is unsupported.

### The native library cannot be opened

- Symptom: `initialize()` throws the platform's own FFI error (for example that `yuv_ffi.dll` or `libyuv_ffi.so` cannot
  be loaded), or `flutter test` fails on the first processing call.
- Check: in an app, was it rebuilt after the dependency was added or upgraded? In a plain Dart VM or `flutter test`, is
  the library on the library search path?
- Action: rebuild the app (`flutter clean`, then build). For tests build the library from `src/` and add its directory
  to the search path. Fix the cause and call `initialize()` again; the failed attempt was not cached.

### `StateError`: the native library does not export required ABI v1 symbols

- Symptom: `initialize()` throws a `StateError` that lists missing `yuv_*_v1` symbols.
- Check: is an older or foreign `yuv_ffi` library earlier on the search path than the one built with this version?
- Action: remove the stale library or rebuild from the matching version. Initialization checks every symbol on purpose
  instead of silently reporting operations as unsupported.

### `StateError`: `Failed to load WASM loader script`

- Symptom: on Web, `initialize()` throws and the page has no processed images.
- Check: open the browser's network panel and look for the request to
  `assets/packages/yuv_ffi/assets/wasm/yuv_ffi.js`. A 404 means the file is not served at that path (a wrong base path or
  an incomplete upload of the build output).
- Action: serve the whole `build/web` output with the app's base path set correctly. Call `initialize()` again after
  fixing it; the failed script tag is removed so that the retry loads a fresh one.

### `StateError`: `WASM module factory "createYuvFfiModule" was not found`

- Symptom: on Web the script loaded but initialization still throws.
- Check: is the script that was served the generated `yuv_ffi.js` of this version, or an old cached file or a proxy
  page?
- Action: clear the cache and redeploy the build output; make sure the response for the script URL is the JavaScript file.

### An operation throws on Web right after startup

- Symptom: an `UnsupportedError` saying the Web backend has not finished `YuvFfi.initialize()`, or a `StateError` saying
  to call `YuvFfi.initialize()` before image operations, from `applyRotation`, `toBgraBytes` or another call during the
  first frames.
- Check: did the call start before the awaited `initialize()` finished (for example in a widget's `initState` without
  waiting)?
- Action: delay the first image work until `initialize()` completes, for instance by awaiting it in `main` before
  `runApp`.

### `UnsupportedError` for an operation and formats on Web or native

- Symptom: an error names an operation and a source format (for example `chromaSwap` with I420).
- Check: `capabilities.supports(operation, sourceFormat: ...)` returns `false` for it. `chromaSwap` only supports NV12.
- Action: convert to a supported format first, or choose another operation.

### `YuvNativeException`

- Symptom: an exception with a `statusCode` and the name of the `operation`.
- Check: status 4 means geometry, stride or span arithmetic could not be carried out, 5 is an allocation failure and 6 is
  an internal failure.
- Action: reduce the image size or the work, then retry. The image keeps its bytes, size and revision after a failed
  call, so retrying is safe. If it repeats, report the operation and `statusCode` in the
  [issue tracker](https://github.com/Anfet/yuv_ffi/issues).

## Related pages

- [Processing and mutations](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations): errors raised by individual calls.
- [Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images): presenter errors and the shader path.
- [Migration guide](https://github.com/Anfet/yuv_ffi/blob/main/MIGRATION.md): moving from 0.2.4 or the retracted 0.4.0.
- [yuv_camera wiki](https://github.com/Anfet/yuv_camera/wiki): camera-specific platform notes.

## Verification boundaries

The declared Flutter floor is 3.44.0; recorded release validation used Flutter 3.44.9, so it does not independently
verify the minimum SDK. Safari, Firefox and mobile Web are unverified. Custom asset placement, CDN hosting and strict
CSP for the WASM module, and static CocoaPods linkage, remain unverified.
Image-operation `--wasm` evidence in Chrome does not establish camera `--wasm` support in `yuv_camera`.
