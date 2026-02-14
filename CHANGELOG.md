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
