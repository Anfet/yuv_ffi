## 0.3.0

### Breaking changes

- Converted `swapNv()` and the format conversion methods (`toYuvNv21()`, `toYuvI420()`, `toYuvBgra8888()`) to in-place behavior. They mutate the current image and return `this` instead of returning a new instance. Call `copy()` first to keep the previous semantics, e.g. `image.copy().toYuvI420()`.
- Migrated the Web interop layer from the removed `dart:js_util` APIs to `dart:js_interop` + `dart:js_interop_unsafe`.
- Moved frame revision off the public interface; implementations that cannot report mutations no longer participate in revision-keyed caching.
- Removed the `getBytes` alignment tail and the orphan NV21 RGB declaration from the native surface.
- `nv21` keeps its established `(U,V)` sample order. This is deliberate and is documented as a deprecated migration path rather than silently corrected.
- Raised the minimum supported SDK to Dart `^3.10.0` / Flutter `>=3.38.0`.
- Excluded the 32-bit `x86` Android ABI from the plugin's native build (`armeabi-v7a`, `arm64-v8a`, `x86_64` only). Flutter has shipped no `x86` native binaries since 3.35 and Google Play never accepted `x86` as a supported ABI for Flutter apps; it only ever mattered for legacy 32-bit emulator images, which the ABI v1 struct layout (a fixed 64-bit `sizeof(void*)` layout) cannot support. A consuming app that still explicitly requests `x86` (e.g. via its own `abiFilters` or an old x86 emulator image) will no longer build against this plugin.

### Changes

- Added checked native arithmetic helpers for addition, multiplication, ceil-half, plane span and sample offset. Overflow is detected before any pointer arithmetic or memory access, replacing signed `int` expressions that could overflow before reaching `size_t`.
- Added internal validated const/mutable plane and frame views that carry actual buffer lengths and validate format IDs, plane counts, sample sizes, independent row/pixel strides, minimum spans and destination geometry.
- Padded and gapped plane layouts are accepted with larger positive strides; row gaps, pixel gaps and bytes beyond the minimum span stay padding and are never treated as logical sample data.
- Added a C unit test harness with `BUILD_TESTING`, strict compiler warnings and sanitizers where the toolchain supports them. It is off by default and does not affect the normal plugin build.
- Validated image geometry and planes before any FFI call, and made sequential native allocations exception-safe.
- Corrected native custom-stride and odd-size conversion safety, and rejected mismatched I420 chroma strides declared in metadata.
- Repacked padded BGRA planes on the Web backend and kept the declared layout of a padded BGRA plane intact.
- Preserved the Y plane during `swapNv()`.
- Hardened the save/load codec: it reads the stream sequentially, judges plane geometry from the header before reading the body, treats EOF as the payload boundary, and catches trailing bytes that arrive after the payload's own chunk.
- Pinned the IO and Web initialization contract, and cached the native bindings instance.
- Loaded the native library by its installed name instead of a CMake build-tree path.
- Removed a failed loader script tag so a retry can succeed.
- Narrowed `ffigen` to the ABI the package actually uses and switched the native build to an explicit source list.
- Enabled optimization for native builds and SIMD for the WASM artifacts, and rebuilt those artifacts from the fixed C sources.
- Added a Web reference conversion matrix and an independent `test_pattern_512` reference, and made the reference matrix skip honestly when no native library is present.
- Documented the approved public Dart API and native C ABI contract for `0.3.0` in `doc/api-abi-0.3-design.md`.
- Upgraded `ffigen` to `^21.0.0`, `ffi` to `^2.2.0`, `build_runner` to `^2.15.1`, `flutter_lints` to `^6.0.0` and `image` (dev) to `^4.10.1`, and regenerated the native bindings; the output is formatting-only (ffigen's newer, more compact function-signature style), with the same symbols and struct layout confirmed by `tool/verify_bindings_audit.dart`.
- Added a dedicated Android CI build job that exercises the plugin's `externalNativeBuild`/CMake wiring through a real `flutter build apk` (YUV-24).

### Notes

- Web remains a partial WASM backend and is not at feature parity with the native backends.
- The versioned status-returning native ABI described in `doc/api-abi-0.3-design.md` is designed and approved, but not yet implemented; the operations still expose the pre-`0.3` entry points.

## 0.2.4

### Breaking changes

- Converted `swapNv()` and format conversion methods (`toYuvNv21()`, `toYuvI420()`, `toYuvBgra8888()`) to in-place behavior. These methods now mutate the current image and return `this` instead of returning a new image instance.
- If you need the previous "return new object" behavior, call `copy()` first, e.g. `image.copy().toYuvI420()`.

### Changes

- Migrated Web JS interop compatibility layer from removed `dart:js_util` APIs to a local shim built on `dart:js_interop` + `dart:js_interop_unsafe`.
- Updated package Web implementation imports to use the new compatibility shim:
  - `lib/src/loader/impl/wasm_loader_web.dart`
  - `lib/src/yuv/impl/web/yuv_web.dart`
- Updated `example/` Web camera preview to use the same compatibility approach.
- Improved pub.dev analyzer compatibility for current stable SDK/runtime used by pub points checks.
- Fixed desktop (`Windows`/`Linux`) example camera startup by skipping `camera` plugin initialization (`availableCameras()`), preventing `MissingPluginException` on platforms without camera plugin implementation.
- Updated example camera preview wiring to support desktop WebRTC-only flow without requiring `CameraController`.
- Kept `CameraController` required for mobile/web preview paths and added explicit argument validation in platform-specific preview builders.

## 0.2.3

### Changes

- Fixed Web JS interop imports for compatibility with lower dependency bounds used by pub.dev static analysis:
  - replaced `package:js/js_util.dart` with `dart:js_util` in package Web implementation files.
- Fixed the same Web interop import in `example/` Web camera preview implementation.
- Removed explicit direct `js` dependency declarations from package manifests.
- Improved pub.dev static analysis compatibility (`pub downgrade` + `flutter analyze` flow).

## 0.2.2

### Changes

- Added dedicated Web parity test files under `test/web/`:
  - `yuv_web_wasm_test.dart` (smoke coverage),
  - `wasm_parity_conversions_test.dart`,
  - `wasm_parity_transforms_test.dart`.
- Added browser-run Web tests execution in CI (`.github/workflows/ci.yml`) over all `test/web/*.dart` files.
- Updated README with explicit local commands for running Web tests in Chrome.
- Updated README credits formatting with explicit contributor roles and links.
- Clarified README `nv21` note to reflect observed device output (UV/NV12-like input and incorrect colors after blind U/V swap).
- Synchronized `pubspec.yaml` package version with latest changelog release (`0.2.2`).

## 0.2.1

### Changes

- Expanded Web backend from placeholder no-op behavior to partial WASM-routed `YuvImage` operations.
- Added WASM routing for Web effects and transforms: `blackwhite`, `grayscale`, `negate`, `flipHorizontally`, `flipVertically`, `crop`, `rotate`.
- Added WASM routing for Web blur methods: `gaussianBlur`, `boxBlur`, `meanBlur`.
- Added WASM routing for Web conversion flow: `fromRgba8888`, `toYuvI420`, `toYuvNv21`, `toBgra8888`, `swapNv`.
- Updated WASM build export list in `tool/wasm/build_wasm.sh` for newly routed symbols.
- Clarified documentation to reflect current Web status as in-progress/partial (not feature-complete).
- Added separate Web test suite files under `test/web/` and wired browser-based execution in CI.
- Added explicit credits section in README.

## 0.2.0

### Breaking changes

- Added mandatory async bootstrap: `await YuvFfi.ensureInitialized()` before package usage.
- Loader API unified under async `ensureInitialized()` across platforms.
- Removed direct public `openYuvLibrary()` usage pattern in favor of unified initialization entrypoint.

### Changes

- Added public bootstrap API export: `YuvFfi` in `package:yuv_ffi/yuv_ffi.dart`.
- Kept IO binding usage (`ffiBingings`) intact after initialization.

## 0.1.2

- Fixed `YuvImageWidget` frame decoding stability by switching to direct pixel decode (`decodeImageFromPixels`) in the image provider path.
- Fixed BGRA export for padded rows: `toBgra8888()` now repacks BGRA data to a tight `width * height * 4` buffer when source row stride contains padding.
- Added regression coverage for padded BGRA row-stride conversion.
- Added golden test for `YuvImageWidget` rendering based on `test/assets/test_pattern_512.png`.
- Added and refined widget tests for frame builder delegation, size propagation, and error builder behavior.
- Clarified and synchronized release documentation for pub.dev publishing.

## 0.1.1

- Added comprehensive conversion/transform tests with a real test asset (`test/assets/test_pattern_512.png`), including flips, crop, rotations, grayscale/blackwhite/negate, conversion round-trips, serialization, and blur smoke tests.
- Added widget tests for `YuvImageWidget` (frame builder delegation, size propagation, error builder behavior) using asset-based image bytes.
- Updated Web/unsupported backend from throwing stubs to safe no-op placeholders in `lib/src/yuv/impl/yuv_stub.dart` to keep API usage non-crashing.
- Documented current Web status as stub-only in `README.md` and `AGENTS.md`.
- Improved `YuvImageWidget` image loading path and builder delegation behavior; strengthened provider error handling and stream/descriptor cleanup.
- Added API documentation comments (dartdoc) for public image types, enums, planes, and widgets.
- Polished `example/` app:
  - fixed persisted file path mismatch (`image.yuv`),
  - added safe async navigation handling (`mounted` check),
  - improved camera stream re-subscription lifecycle handling,
  - optimized `FaceRectPainter.shouldRepaint`,
  - replaced debug `print` calls with `debugPrint`.
- Analyzer configuration keeps generated bindings excluded (`lib/src/functions/bindings/yuv_ffi_bingings.dart`).

## 0.1.0

- Initial public release.
- Native C/FFI image processing for `i420`, `nv21` (project-specific UV layout), and `bgra8888`.
- Added conversions, crop/rotate/flip, grayscale/negate/blackwhite, and blur operations.
- Added serialization helpers and Flutter widget export.
