# yuv_ffi

`yuv_ffi` is a Flutter/Dart package for high-performance image processing on YUV/BGRA frames using native C + FFI.

## Features

- YUV format conversions (`i420`, `nv21`, `bgra8888`)
- Crop, rotate, flip
- Grayscale, black/white, negate
- Mean/box/Gaussian blur
- Plane-based API with row/pixel stride support
- In-memory save/load helpers for frame serialization

## Important format note (`nv21`)

In this project, the `nv21` label is intentionally used for a buffer with **UV** chroma order (practically closer to `NV12`), not classic `VU` NV21.

This is a deliberate internal contract.  
When integrating with external camera/codec pipelines, swap U/V if needed.

## Installation

From pub.dev:

```yaml
dependencies:
  yuv_ffi: ^0.1.0
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

final image = YuvImage.i420(1280, 720);
image.fromRgba8888(rgbaBytes); // rgbaBytes.length must be width * height * 4

final preview = image
    .rotate(YuvImageRotation.rotation90)
    .grayscale()
    .toBgra8888();
```

## Public API (Dart)

Exports from `package:yuv_ffi/yuv_ffi.dart`:

- `YuvImage`
- `YuvPlane`
- `YuvFileFormat`
- `YuvImageRotation`
- `YuvImageWidget`

Main constructors:

- `YuvImage.i420(width, height, ...)`
- `YuvImage.nv21(width, height, ...)`
- `YuvImage.bgra(width, height, ...)`

## Platform support

- Android: native FFI
- iOS: native FFI
- macOS: native FFI
- Windows: native FFI
- Linux: native FFI
- Web: package builds, but `YuvImage` processing is currently a **stub/no-op** implementation (placeholder only)

## TODO

- Implement a real web backend for `YuvImage` operations.
- Replace current web stub behavior (no-op placeholders, no native-quality processing).

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

## License

[MIT](./LICENSE)
