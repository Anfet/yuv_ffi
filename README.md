# yuv_ffi

`yuv_ffi` is a Flutter/Dart package for high-performance image processing on YUV/BGRA frames using native C + FFI.

## Features

- YUV format conversions (`i420`, `nv12`, `bgra8888`)
- Crop, rotate, flip
- Grayscale, black/white, negate
- Mean/box/Gaussian blur
- Live, directly writable plane-based API with row/pixel stride support
- Typed capabilities query (`YuvFfi.initialize()`) instead of guessing what a backend supports
- Binary codec v2 for frame serialization (`encodeTo`/`YuvImage.decode`)

## Important format note (`nv12`/`nv21`)

Camera input on target devices is often delivered in **UV** interleaving (closer to `NV12` than
classic `NV21` VU). This project's `nv12` format keeps that observed `(U, V)` byte order rather
than the literal NV21 `(V, U)` order; do not blindly swap U/V on these inputs, or you get incorrect
colors. The legacy `nv21` name from `0.2.4` is a deprecated alias for the same storage: a `nv21`-built
image reports `format == YuvPixelFormat.nv12`.

## Installation

From pub.dev:

```yaml
dependencies:
  yuv_ffi: ^0.4.0
```

Or from Git:

```yaml
dependencies:
  yuv_ffi:
    git:
      url: https://github.com/Anfet/yuv_ffi.git
```

## Quick start

```dart
import 'package:yuv_ffi/yuv_ffi.dart';

// Required before the capability-gated 0.4.0 API on every platform.
// Repeated calls are safe: success is cached, failure is not.
final capabilities = await YuvFfi.initialize();

final image = YuvImage.i420(1280, 720);
image.applyRgbaBytes(rgbaBytes); // rgbaBytes.length must be width * height * 4

image.applyRotation(YuvImageRotation.rotation90);
image.applyGrayscale();
final preview = image.toBgraBytes();
```

Every `apply*` method mutates the receiver in place, returns `identical(this)`, and throws
`UnsupportedError` up front (before touching any byte) if the backend or format pair doesn't
support it — check first with `capabilities.supports(...)` if you need to branch instead of catch:

```dart
if (capabilities.supports(YuvOperation.gaussianBlur, sourceFormat: image.format)) {
  image.applyGaussianBlur(radius: 8, sigma: 8);
}
```

Methods that return a new, independent image instead of mutating (`toI420()`, `toNv12()`,
`toBgra()`, `cropped(...)`, `rotated(...)`, `copy()`) never touch the source.

## Live planes and `markDirty()`

`yPlane`, `uPlane`, `vPlane` and `planes` expose the image's real backing storage, not a copy —
writing into `image.yPlane.bytes` mutates the image directly. That kind of direct write cannot be
detected automatically, so it does not by itself refresh a `YuvImageWidget` built from that image
(which caches by revision). Call `markDirty()` afterwards:

```dart
image.yPlane.bytes[0] = 0xFF;
image.markDirty(); // otherwise a cached widget keeps showing the previous frame
```

`apply*` methods and `applyPlanes(...)` already advance the revision themselves; `markDirty()` is
only needed after writing straight into plane bytes. Calling it when nothing changed is harmless.

To replace an image's format/geometry/planes wholesale in one atomic step, use `applyPlanes(...)`
instead of assigning planes one at a time — every previously obtained `planes`/`yPlane`/`uPlane`/
`vPlane` reference is stale after it succeeds.

## Public API (Dart)

Exports from `package:yuv_ffi/yuv_ffi.dart`:

- `YuvImage` (plus the deprecated legacy extension, `DeprecatedYuvImageApi`)
- `YuvPlane`
- `YuvPixelFormat` (`i420`, `nv12`, `bgra8888`) and the deprecated `YuvFileFormat`
- `YuvImageRotation`
- `YuvOperation`, `YuvCapabilities`
- `YuvNativeException`
- `YuvImageWidget`
- `YuvFfi` (`initialize()`)

Main constructors:

- `YuvImage.i420(width, height, ...)`
- `YuvImage.nv12(width, height, ...)`
- `YuvImage.bgra(width, height, ...)`
- `YuvImage.allocate(format, width, height)` — blank, tightly packed image
- `YuvImage.fromRgbaBytes(bytes, width:, height:, format:)` — convert RGBA8888 input into a new image

## Migrating from `0.2.4`

The published `0.2.4` API still compiles: its old instance methods now live in a deprecated
`DeprecatedYuvImageApi` extension that forwards to its `0.4.0` replacement, so existing code keeps
working (with deprecation warnings) while you migrate at your own pace. New code should use the
right-hand side below.

| `0.2.4` (deprecated) | `0.4.0` |
| --- | --- |
| `YuvFfi.ensureInitialized()` | `YuvFfi.initialize()` — now returns `YuvCapabilities` |
| `image.fromRgba8888(bytes)` | `image.applyRgbaBytes(bytes)` |
| `image.rotate(r)`, `.crop(rect)`, `.flipHorizontally()`, `.flipVertically()` | `image.applyRotation(r)`, `.applyCrop(rect)`, `.applyFlipHorizontal()`, `.applyFlipVertical()` |
| `image.grayscale()`, `.blackwhite()`, `.negate()` | `image.applyGrayscale()`, `.applyBlackWhite()`, `.applyNegate()` |
| `image.gaussianBlur(radius:, sigma:)`, `.boxBlur(radius:, rect:)`, `.meanBlur(radius:, rect:)` | `image.applyGaussianBlur(radius:, sigma:)`, `.applyBoxBlur(radius:, region:)`, `.applyMeanBlur(radius:, region:)` |
| `image.toYuvI420()`, `.toYuvNv21()`, `.toYuvBgra8888()` (in-place) | `image.applyFormat(YuvPixelFormat.i420 / .nv12 / .bgra8888)` (in-place), or `image.toI420()` / `.toNv12()` / `.toBgra()` for a new independent image |
| `image.swapNv()` | `image.applyChromaSwap()` (NV12 only); convert first with `applyFormat(YuvPixelFormat.nv12)` if the source isn't already NV |
| `image.getBytes()` | `image.toBytes()` |
| `image.toBgra8888()` | `image.toBgraBytes()` |
| `image.y` / `.u` / `.v` | `image.yPlane` / `.uPlane` / `.vPlane` |
| `image.copy(blank: true)` | For a tight layout, `YuvImage.allocate(format, width, height)`. For a padded or pixel-gapped layout, use the matching named factory with zeroed `YuvPlane`s that retain each source plane's `height`, `rowStride`, and `pixelStride`; `allocate` deliberately creates a tight layout. |
| `image.save(sink)` | `image.encodeTo(sink)` |
| `image.load(stream)` (mutates in place) | `YuvImage.decode(stream)` (returns a new image; nothing to mutate) |
| `YuvImage.nv21(...)`, `YuvImage(YuvFileFormat.x, ...)` | `YuvImage.nv12(...)`, `YuvImage.i420(...)` / `.bgra(...)` / `.allocate(...)` |
| `image.format` returning `YuvFileFormat` | `image.format` returning `YuvPixelFormat` (a legacy `nv21`-built image now reports `nv12`) |

Migration details:

- The default I420 chroma pixel stride changed from `2` to `1`. Code that relied on the old gapped
  default must now pass `uvPixelStride: 2` explicitly to `YuvImage.i420(...)`.
- `swapNv()`'s old two-step "convert then swap" behavior for a non-NV source is not a single
  `0.4.0` method: call `applyFormat(YuvPixelFormat.nv12)` then `applyChromaSwap()` explicitly.
- Frames serialized with `0.2.4` (`save`/`load`, wire format v1) are not readable by `0.4.0`'s
  `decode`/`load`. Migrate them in two app versions: while the app still uses `0.2.4`, read each v1
  frame and persist its format, width, height, per-plane row/pixel strides, and raw plane bytes in
  an application-owned intermediate representation. After upgrading to `0.4.0`, recreate the image
  from that representation with the matching named factory and `YuvPlane` values, then write v2 via
  `encodeTo`. A `0.2.4` re-save is still v1 (and may include trailing zero padding); do not transfer
  the raw v1 file as the intermediate record. `0.4.0` rejects v1 on read with `FormatException`.

Adding the full `0.4.0` `apply*`/`to*` surface to the `YuvImage` interface is a breaking change for
any external `implements YuvImage` class: such a class must implement every new required member
(the deprecated extension still works on it, forwarding to those members) to keep compiling.

## Platform support

- Android: native FFI (`armeabi-v7a`, `arm64-v8a`, `x86_64`; the 32-bit `x86` ABI is not built — Flutter has shipped no `x86` binaries since 3.35 and Google Play never accepted it as a supported ABI for Flutter apps). Verified: plugin/example build via CI (`android-native-build`).
- iOS: native FFI. Verified: plugin/example build only (`flutter build ios --debug --no-codesign`); no on-device/runtime smoke.
- macOS: native FFI. Verified: build and app-runtime smoke (real conversion + effect call from a built app) on macOS 15.6.1 arm64.
- Windows: native FFI. Verified: build and app-runtime smoke (`flutter drive`).
- Linux: native FFI. Verified in CI build/smoke jobs; not re-run on a local Linux host.
- Web: package builds and uses a **partial WASM backend** (work in progress, not feature-complete)

macOS/Linux app-runtime and iOS build verification above reflect the YUV-06 result, accepted and
covered by [CI run 35775516094](https://github.com/Anfet/yuv_ffi/actions/runs/35775516094).

## Example camera preview notes

In `example/`, camera preview behavior differs by platform backend:

- Mobile (Android/iOS): real-time frame stream is available, so preview can run per-frame `YuvImage` transforms.
- Web: real-time frame extraction path is available in the example and supports transformed preview.
- Desktop (Windows/macOS/Linux): the example uses fast native preview rendering and a throttled frame-capture
  path for processing. Full per-frame transformed live preview is not currently provided by this desktop setup.

Processing backend note:

- YUV conversions/transforms are native on IO platforms (Android/iOS/macOS/Windows/Linux) via C + FFI.
- Web uses the current partial WASM backend (work in progress, not parity-complete with native backends).

## Initialization

Call package bootstrap once at app start. On every platform it must complete before the
capability-gated `0.4.0` API: every `apply*` method, `cropped(...)`, `rotated(...)`, `toI420()`,
`toNv12()`, and `toBgra()`. On IO/native, calling one of these before bootstrap throws
`UnsupportedError` because the backend capability has not yet been determined; it does not mean
the operation is unsupported.

IO/native retains the pre-bootstrap lazy behavior for constructors, plane access, `copy`,
`applyPlanes`, `toBytes`, `toBgraBytes`, `toImage`, `encodeTo`, `YuvImage.decode`,
`YuvImage.fromRgbaBytes`, and the deprecated legacy instance methods. Repeated calls are safe: a
successful initialization is cached, a failed one is not, so the next call retries.

```dart
import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final capabilities = await YuvFfi.initialize();
  runApp(MyApp(capabilities: capabilities));
}
```

`capabilities.supports(operation, sourceFormat: ..., destinationFormat: ...)` reports whether a
given `YuvOperation` is available for a format (pair), reflecting what the loaded native library or
WASM module actually exports on this run — every isolate initializes separately, so a fresh
isolate must call `YuvFfi.initialize()` itself.

## TODO

- Complete and harden Web WASM parity with native backends.
- Expand Web parity and edge-case coverage (odd sizes, stride/pixelStride combinations, rect boundaries).

## Web WASM status (current stage)

WASM work is split into phases.  
Current phase includes:

- WASM build script (`tool/wasm/build_wasm.sh`)
- package asset layout for generated artifacts (`assets/wasm/`)
- Web module loader scaffold (`lib/src/loader/wasm_loader.dart`)
- WASM-routed `YuvImage` operations on Web, all of them through the versioned
  `yuv_*_v1` ABI (the same one the native backend calls):
  - conversion: `applyRgbaBytes`, `applyFormat`, `toI420`/`toNv12`/`toBgra`
  - transforms: `applyCrop`, `applyRotation`, `applyFlipHorizontal`, `applyFlipVertical`
  - effects: `applyGrayscale`, `applyBlackWhite`, `applyNegate`
  - blur: `applyGaussianBlur`, `applyBoxBlur`, `applyMeanBlur`
  - `applyChromaSwap`
  
  Which of these actually succeed on Web depends on which `yuv_*_v1` symbols the loaded
  `.wasm` module exports: query `capabilities.supports(...)` (from `YuvFfi.initialize()`) rather
  than assuming every operation above is available in a given build.

The Web backend stages ABI v1 descriptors in WASM linear memory at the wasm32
layout `src/yuv/abi/h/yuv_abi_v1.h` declares, and shares the format mapping,
padding-preservation rule and `YuvStatus` contract with the native backend, so
an operation behaves the same on both. A non-zero status throws before any
result byte is read back, leaving the image untouched, and a WASM module missing
an ABI v1 export is rejected by symbol name rather than failing inside a
`ccall`.

Limitations:

- Web backend is still in-progress and should be treated as non-final. Running
  on ABI v1 aligns the two backends' behavior; it does not by itself make Web
  feature-complete with native.
- Web tests are maintained separately under `test/web/` and are intended for browser runner execution.

### Known limitations (explicit)

- Web backend parity is validated by tests, but is not yet declared feature-complete with native backends.
- Browser runtime constraints apply on Web (WASM init lifecycle, browser memory/runtime limits).
- Example desktop camera preview uses fast native preview plus throttled processing path,
  not full per-frame transformed live feed.

### Web parity matrix (v1)

This matrix defines current parity targets and validation scope for Web WASM against native backends.

- `Conversions`:
  scope: `applyRgbaBytes`, `applyFormat`, `toI420`/`toNv12`/`toBgra`, `toBgraBytes`
  validation: round-trip quality thresholds and dimension checks
  (`test/web/wasm_parity_conversions_test.dart`)
- `Geometry transforms`:
  scope: `applyCrop`, `applyRotation`, `applyFlipHorizontal`, `applyFlipVertical`
  validation: exact/predictable BGRA checks
  (`test/web/wasm_parity_transforms_test.dart`)
- `Effects/blur`:
  scope: `applyGrayscale`, `applyBlackWhite`, `applyNegate`, `applyBoxBlur`, `applyMeanBlur`, `applyGaussianBlur`
  validation: web runtime smoke coverage (`test/web/yuv_web_wasm_test.dart`)
- `Edge cases`:
  scope: odd sizes (`1x1`, `3x5`, `127x255`), custom rowStride/pixelStride,
  out-of-bounds crop, transform chains
  validation: dedicated edge-case coverage (`test/web/wasm_parity_edge_cases_test.dart`)

Acceptance intent:

- Behavior parity: no crashes, deterministic geometry, expected dimensions/plane layouts.
- Numeric parity: conversion quality remains within test thresholds (`MAE`) for Web round-trips.
- Stride parity: custom row/pixel stride layouts produce stable BGRA output.

Build command (Shell; macOS + Windows via Git Bash/WSL):

```sh
sh ./tool/wasm/build_wasm.sh
```

Smoke checks:

```sh
flutter test
```

Web WASM bootstrap gate (real app asset bundle):

```sh
# Terminal 1: start a matching ChromeDriver.
chromedriver --port=4444

# Terminal 2: run the same integration harness as CI.
cd example
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/wasm_bootstrap_test.dart \
  -d web-server --browser-name=chrome --headless
```

`flutter test --platform chrome` does not serve the package asset bundle and
must not be used for WASM runtime tests. The full Web reference matrix remains
the YUV-12 scope and will run through this integration harness.

On Windows Git Bash, the build script auto-falls back to `emcc.bat`/`emcc.cmd`
when plain `emcc` is not resolvable by `command -v`.

## Build notes

Native code is in `src/` and is built as a shared library per platform:

- Android/Linux: `libyuv_ffi.so`
- Windows: `yuv_ffi.dll`
- Apple platforms: platform-specific dynamic/static linkage via plugin build setup

## Generated bindings

Do not edit `lib/src/functions/bindings/yuv_ffi_bingings.dart` manually.  
It is generated via `ffigen` from `src/yuv_ffi.h` using `ffigen.yaml`.

Regenerate with:

```bash
flutter pub run ffigen --config ffigen.yaml
```

## Credits

- Oleg Toplionkin (Author & Maintainer) - https://github.com/Anfet
- OpenAI Codex (Engineering Assistant: tests and WASM bindings integration) - https://openai.com/

## License

[MIT License](https://opensource.org/license/mit/)
