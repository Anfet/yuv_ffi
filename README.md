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

In this project, the `nv21` API label is intentionally kept for compatibility, but camera input on target devices is often delivered in **UV** interleaving (closer to `NV12` than classic `NV21` VU).

This is based on observed device output in real pipelines.  
Do not blindly swap U/V: on these inputs, swapping chroma produces incorrect colors.

## Installation

From pub.dev:

```yaml
dependencies:
  yuv_ffi: ^0.1.2
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

await YuvFfi.ensureInitialized();

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
- `YuvFfi` (`ensureInitialized()`)

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
- Web: package builds and uses a **partial WASM backend** (work in progress, not feature-complete)

## Initialization

Call package bootstrap once at app start:

```dart
import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.ensureInitialized();
  runApp(const MyApp());
}
```

## TODO

- Complete and harden Web WASM parity with native backends.
- Expand Web parity and edge-case coverage (odd sizes, stride/pixelStride combinations, rect boundaries).

## Web WASM status (current stage)

WASM work is split into phases.  
Current phase includes:

- WASM build script (`tool/wasm/build_wasm.sh`)
- package asset layout for generated artifacts (`assets/wasm/`)
- Web module loader scaffold (`lib/src/loader/wasm_loader.dart`)
- WASM-routed `YuvImage` operations on Web:
  - conversions: `fromRgba8888`, `toYuvI420`, `toYuvNv21`, `toBgra8888`
  - transforms: `crop`, `rotate`, `flipHorizontally`, `flipVertically`
  - effects: `grayscale`, `blackwhite`, `negate`
  - blur: `gaussianBlur`, `boxBlur`, `meanBlur`
  - `swapNv`

Limitations:

- Web backend is still in-progress and should be treated as non-final.
- Web tests are maintained separately under `test/web/` and are intended for browser runner execution.

Build command (Shell; macOS + Windows via Git Bash/WSL):

```sh
sh ./tool/wasm/build_wasm.sh
```

Smoke checks:

```sh
flutter test
```

Web tests (browser runner):

```sh
flutter test -d chrome test/web/yuv_web_wasm_test.dart
flutter test -d chrome test/web/wasm_parity_conversions_test.dart
flutter test -d chrome test/web/wasm_parity_transforms_test.dart
```

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

[MIT](./LICENSE)
