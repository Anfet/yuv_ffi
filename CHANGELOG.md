## 0.4.0

First published release after `0.2.4`. Implemented against [the 0.4.0 design](doc/api-abi-0.4-design.md).
See the README's "Migrating from `0.2.4`" section for a full method-by-method mapping.

### Breaking changes

- Replaced the public storage format with `YuvPixelFormat` (`i420`, `nv12`, `bgra8888` with stable wire IDs). `YuvImage.format` now returns `YuvPixelFormat`; the old `YuvFileFormat` enum is deprecated and kept only for the `nv21` legacy entry points. A legacy `nv21`-built image reports `format == YuvPixelFormat.nv12`.
- Added the full `apply*` (in-place, capability-gated, returns `identical(this)`) and `to*` (independent result) method surface to the `YuvImage` interface. Legacy `0.2.4` instance methods remain available through the deprecated `DeprecatedYuvImageApi` extension, preserving their dispatch semantics (no `YuvFfi.initialize()` requirement) and byte behavior, including the historical `nv21` UV order and `swapNv()`'s in-place two-step convert-then-swap. Any external `implements YuvImage` class must add the new required interface members to keep compiling.
- Changed the default I420 chroma pixel stride from `2` to `1`. Code that relied on the old gapped default must now pass `uvPixelStride: 2` explicitly to `YuvImage.i420(...)`.
- Added `encodeTo(sink)` and the static `YuvImage.decode(stream)`. `save`/`load` moved to the deprecated extension: `save` forwards to `encodeTo` with identical bytes; `load` mutates in place through a package-private atomic state-replacement path and throws `UnsupportedError` without mutating on a foreign `implements YuvImage` (the same fallback shape as `swapNv()`).
- Codec now writes and reads only wire format v2 (`formatId` from `YuvPixelFormat.wireId` instead of a string `format` field). A v1 payload written by published `0.2.4` is rejected with `FormatException` on read; there is no v1 writer and no automatic migration. To retain old frames, a `0.2.4` app must first load each frame and persist format, dimensions, plane strides, and bytes in its own intermediate representation; after upgrading, recreate the image and write v2 with `encodeTo`. Do not use a v1 re-save as the intermediate record: `0.2.4` may append zero padding to its output.
- `YuvFfi.ensureInitialized()` is deprecated in favor of `YuvFfi.initialize()`, which now returns a `YuvCapabilities` snapshot instead of `void`. A negative `capabilities.supports(...)` result, or calling an unsupported operation directly, throws `UnsupportedError` before any allocation, native dispatch, or revision change. Each isolate still initializes independently.
- Image plane getters (`yPlane`, `uPlane`, `vPlane`, `planes`) expose live, directly writable storage. A direct write through them (or `setPixel`/`assignFrom`) is not detected automatically and needs an explicit `markDirty()` call afterwards to refresh revision-keyed caches such as `YuvImageWidget`. `apply*` and `applyPlanes(...)` already advance the revision themselves. `applyPlanes(...)` atomically validates, copies, and replaces the full plane set in one step; every previously obtained plane reference is stale after it succeeds.
- Added typed error handling: `YuvNativeException` now carries a `YuvOperation` and message instead of a bare status/string pair; ABI status codes and loader failures are consistently `ArgumentError`, `UnsupportedError`, or `YuvNativeException` per the design's contract, and a failed operation always leaves bytes, format, geometry and revision unchanged.
- `YuvImageWidget`/`YuvImageProvider` now render through `toBgraBytes()` and cache by the image's revision instead of by identity alone, so a mutated `YuvImage` reused across rebuilds refreshes correctly.
- Android camera frames whose final row omits unused row-stride padding are normalized before building `YuvPlane`, so the live preview and capture path can process the complete frame layout.

### Notes

- Web remains a partial WASM backend: a successful `YuvFfi.initialize()` means the WASM runtime loaded, not that every operation available on native is supported. Query `capabilities.supports(...)` rather than assuming parity.
- `applyChromaSwap()` is valid only on an NV12-formatted image on every backend; convert first with `applyFormat(YuvPixelFormat.nv12)` if the source isn't already NV.
- The example app's demo code (`main.dart`, `ext.dart`, `widgets/impl/*`) now targets `apply*`/`to*`/`YuvFfi.initialize()`. Its `integration_test/*` suite intentionally still exercises the deprecated legacy surface where that is the test's actual subject (back-compat/legacy-dispatch contracts).

### Native ABI and platform work included in 0.4.0

This work was developed on the unpublished `release/0.3.0` Git branch. It is part of
the published `0.2.4` → `0.4.0` upgrade, not a separate pub.dev release.

#### Breaking changes

- Moved frame revision off the public interface; implementations that cannot report mutations no longer participate in revision-keyed caching.
- Removed the `getBytes` alignment tail and the orphan NV21 RGB declaration from the native surface.
- Removed the legacy processing ABI. The published native library and the WASM module export the eleven `yuv_*_v1` processing symbols and nothing else: the 40 per-format `yuv420_*`, `nv21_*` and `bgra8888_*` entry points, `nvXX_to_nvYY` and the `YUVDef` descriptor are gone from the headers, the generated FFI bindings and the binaries. A consumer that called those symbols directly through its own FFI lookup must move to the versioned ABI; the legacy `nv21` entry points retain their established `(U,V)` sample order.
- Raised the minimum supported SDK to Dart `^3.10.0` / Flutter `>=3.38.0`.
- Excluded the legacy 32-bit `x86` emulator ABI from the plugin's native build (`armeabi-v7a`, `arm64-v8a`, `x86_64` only). This target list is not a 64-bit-pointer requirement: the ABI v1 header fixes descriptor sizes and offsets and checks 8-byte alignment for `uint64_t` and `double`, while `armeabi-v7a` remains supported. A consuming app that explicitly requests the excluded `x86` target through its own `abiFilters` will not build against this plugin.

#### Changes

- Routed every public native-backend and Web-backend operation through the versioned `yuv_*_v1` ABI. The per-format `yuv420_*`, `nv21_*` and `bgra8888_*` entry points, and `nvXX_to_nvYY`, are no longer called from Dart on either backend.
- Moved the Web backend onto the same ABI v1 descriptors the native backend uses: it stages `YuvConstFrameV1`/`YuvMutableFrameV1` and the versioned options structs in WASM linear memory at the wasm32 layout the C header declares, and maps `YuvStatus` through the shared status contract. Web and native now share one transport, one format mapping and one padding-preservation rule, so an operation behaves the same on both. Web remains a partial WASM backend.
- Web operations now report a failure instead of silently continuing: a non-zero `YuvStatus` throws before any result byte is read back, so a failed Web operation leaves bytes, geometry and the revision counter unchanged, and a WASM module missing an ABI v1 export is rejected by symbol name rather than failing inside a `ccall`.
- A failed operation now leaves the image completely unchanged: a non-zero native status is raised before any result byte is read back, so bytes, format, geometry and the revision counter all keep their previous values. This holds for `swapNv()` on an I420 or BGRA image too, which needs two native calls: the conversion to NV12 and the chroma swap both complete on drafts, and the result is published once, so a chroma swap that fails no longer leaves the image converted.
- An image's declared plane layout survives an in-place operation. Only active samples are written, so row padding, pixel gaps and bytes past the last sample keep their previous contents instead of being repacked.
- Blur and effects accept a padded BGRA plane, which the previous per-format kernels could not address safely and which the Dart layer therefore rejected.
- Fixed `I420 <-> NV12` conversion, which ran through a YUV->RGB->YUV round trip and so perturbed every Y sample and re-averaged chroma that was already at final resolution. Both formats store identical samples, so the conversion now moves them directly.
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
- Documented the native C ABI and public Dart API contract in [the 0.4.0 design](doc/api-abi-0.4-design.md).
- Upgraded `ffigen` to `^21.0.0`, `ffi` to `^2.2.0`, `build_runner` to `^2.15.1`, `flutter_lints` to `^6.0.0` and `image` (dev) to `^4.10.1`, and regenerated the native bindings; the output is formatting-only (ffigen's newer, more compact function-signature style), with the same symbols and struct layout confirmed by `tool/verify_bindings_audit.dart`.
- Added a dedicated Android CI build job that exercises the plugin's `externalNativeBuild`/CMake wiring through a real `flutter build apk` (YUV-24).

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
