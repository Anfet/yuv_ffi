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
