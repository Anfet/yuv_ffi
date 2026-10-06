# yuv_ffi

`yuv_ffi` processes I420, NV12, and BGRA8888 images in Flutter. It provides
conversion, crop, rotation, flips, effects, blur, serialization, and Flutter
image presentation. Native platforms use C through FFI; Web uses a WASM
backend on Flutter's JavaScript and `--wasm` builds.

## Installation

```yaml
dependencies:
  yuv_ffi: 0.5.1
```

Version 0.5.1 is the next available pub.dev release after 0.2.4. Version
0.4.0 was published and later retracted; the migration guidance below also
applies to applications whose lockfile still resolves 0.4.0. Updating from
0.5.0 to 0.5.1 does not require API replacements.

## Requirements

| Platform | Requirement |
| --- | --- |
| Dart | 3.12 or later |
| Flutter | 3.44 or later |
| Android | API 26 or later; `armeabi-v7a`, `arm64-v8a`, or `x86_64` |
| iOS | 13 or later |
| macOS | 10.15 or later |
| Windows | Native FFI backend |
| Linux | Native FFI backend |
| Web | Flutter JavaScript and `--wasm` builds; tested in Chrome |

On iOS and macOS the plugin builds with either Swift Package Manager (the
default in Flutter 3.44 and later) or CocoaPods. Nothing needs to be configured
in your app. The Apple sources live in `darwin/`; the C sources stay in `src/`.

Web operations match the native backend in the checked cases on both the
JavaScript and `--wasm` Flutter builds. `chromaSwap` supports NV12 only, as on
native. Both builds were verified in Chrome. Use `flutter build web` or
`flutter build web --wasm`.
Safari and Firefox have not been verified. Safari 16.4 or later is a technical
minimum for release WASM SIMD, not a tested compatibility claim for this plugin.

## Quick start and initialization

Initialize once in every isolate before calling a capability-gated processing
method. A successful initialization is cached; a failed initialization can be
retried. The returned capabilities describe the operations the loaded backend
can dispatch.

```dart
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final capabilities = await YuvFfi.initialize();
  final image = YuvImage.i420(1280, 720);
  final rgbaBytes = Uint8List(image.width * image.height * 4);

  if (capabilities.supports(
    YuvOperation.convert,
    sourceFormat: image.format,
    destinationFormat: image.format,
  )) {
    image.applyRgbaBytes(rgbaBytes);
  }

  if (capabilities.supports(
    YuvOperation.rotate,
    sourceFormat: image.format,
  )) {
    image.applyRotation(YuvImageRotation.rotation90);
  }

  runApp(Directionality(
    textDirection: TextDirection.ltr,
    child: YuvImageWidget(image: image),
  ));
}
```

On Web, initialization must complete before every `YuvImage` operation. On
native platforms, it must complete before these capability-gated methods:
`applyRgbaBytes`, `applyGrayscale`, `applyBlackWhite`, `applyNegate`,
`applyGaussianBlur`, `applyMeanBlur`, `applyBoxBlur`, `applyCrop`,
`applyFlipHorizontal`, `applyFlipVertical`, `applyRotation`, `applyFormat`,
`applyChromaSwap`, `cropped`, `rotated`, `toI420`, `toNv12`, and `toBgra`.
Constructors, plane access, `copy`, `applyPlanes`, byte conversion, encoding,
and decoding retain native lazy behavior.

## Image mutation and revisions

`apply*` methods mutate their receiver in place and return that same image.
Successful mutations advance `image.revision` once; rejected calls and genuine
no-ops leave it unchanged. `toI420`, `toNv12`, `toBgra`, `cropped`, `rotated`,
`copy`, and `YuvImage.decode` return independent images and do not mutate the
source.

`planes`, `yPlane`, `uPlane`, and `vPlane` expose mutable backing storage.
After directly changing plane bytes, call `markDirty()` so a widget creates a
new cache key. `apply*` and `applyPlanes` already update the revision.

```dart
image.yPlane.bytes[0] = 0xFF;
image.markDirty();
```

`applyPlanes(...)` validates and atomically replaces all planes. Any plane
reference obtained before it succeeds is stale and must be read again.

## Displaying images

Use `YuvImageWidget` for a standalone image. It creates a `YuvImageProvider`,
whose cache key combines the image identity with the captured revision.

```dart
YuvImageWidget(
  image: image,
  boxFit: BoxFit.contain,
)
```

`YuvImageProvider(image)` is available when an `ImageProvider` is required.
For a live stream, `YuvFramePresenter` keeps one current image for display.
`present(frame)` returns `false` while decoding or until the decoded frame has
been rendered, so intermediate frames are dropped. Render it with
`YuvFrameView` and call `dispose()` when the stream ends.

```dart
final presenter = YuvFramePresenter();
presenter.present(image);

final view = YuvFrameView(presenter: presenter);
```

Pass `useShader: true` to `YuvFramePresenter` for shader-backed live frames,
and pass a `YuvFrameOrientation` to `present` to rotate or mirror at draw time.
`YuvFrameView.fit` and `alignment` use `YuvFrameGeometry`; its
`onGeometryChanged` callback exposes the exact overlay mapping.

### Frame geometry and ML Kit

`YuvFrameGeometry` keeps source pixels, ML Kit's upright pixels, and widget
pixels in separate coordinate spaces. Give ML Kit the raw frame with
`orientation.rotation`, then map its bounding boxes through
`MatrixUtils.transformRect(geometry.uprightToView, box)`. Mirroring is applied
only after rotation, so the preview and overlay stay aligned.

```dart
final geometry = YuvFrameGeometry(
  sourceSize: frame.size,
  viewSize: widgetSize,
  orientation: const YuvFrameOrientation(rotation: YuvImageRotation.rotation90, mirrored: true),
  fit: YuvFrameFit.cover,
);
final displayedFrame = geometry.apply(frame);
```

`YuvFrameRenderer` uploads I420 and NV12 planes to the package shader when it
is available, including Web (CanvasKit). Unsupported layouts and shader-load
failures use the pixel-equivalent BGRA fallback instead.

## Formats and plane layout

`YuvPixelFormat.i420` stores separate Y, U, and V planes.
`YuvPixelFormat.nv12` stores Y plus interleaved `(U, V)` chroma bytes.
`bgra8888` is a single packed BGRA plane.

Factories that receive `planes:` default to `YuvPlaneLayout.packed`: they
copy visible samples into tight planes and discard row padding and per-sample
gaps. Pass `layout: YuvPlaneLayout.preserve` to retain the supplied
`rowStride`, `pixelStride`, and padding bytes. `copy`, `decode`, and
`applyPlanes` preserve their plane layouts.

```dart
final padded = YuvImage.i420(
  2,
  2,
  planes: <YuvPlane>[
    YuvPlane(2, 4),
    YuvPlane(1, 2),
    YuvPlane(1, 2),
  ],
  layout: YuvPlaneLayout.preserve,
);

padded.pack();
```

`pack()` removes row padding and pixel gaps in place while preserving visible
samples, format, UV order, size, and orientation. Padding discarded by
`pack()` cannot be recovered; use `copy().pack()` to retain an independent
original image.

### Inserting a patch

`applyPatch` copies an opaque, unscaled image into another image of the same
format without touching destination padding or pixel-gap bytes:

```dart
final fragment = source.cropped(region).rotated(YuvImageRotation.rotation90);
destination.applyPatch(fragment, x: 100, y: 40);
```

The fragment must fit completely. For I420 and NV12, `x` and `y` must be even;
an odd fragment width or height is accepted only at the corresponding right or
bottom edge. This keeps every chroma 2×2 sample wholly inside the patch.

## Capabilities and errors

Call `capabilities.supports(operation, sourceFormat: ..., destinationFormat:
...)` before dispatch when the application needs to choose a path. A
destination format is required only for `YuvOperation.convert`; malformed or
unsupported capability queries return `false`.

Public calls can throw:

- `ArgumentError` for invalid dimensions, planes, byte lengths, geometry, or
  native argument validation.
- `UnsupportedError` when a backend or format pair cannot dispatch an
  operation, including a capability-gated call before initialization.
- `YuvNativeException` for native overflow, allocation, internal failures, or
  an unrecognized native status.
- `StateError` during initialization when Web configuration or runtime setup
  fails, or when a native library lacks a required ABI export.

## Platform status

| Platform | Support | Checked in CI | Checked manually |
| --- | --- | --- | --- |
| Android | Native FFI: `armeabi-v7a`, `arm64-v8a`, `x86_64` | Build, app-runtime smoke, and the 1188-case correctness matrix | Release builds on a physical Pixel 3 for `arm64-v8a` and `armeabi-v7a` |
| iOS | Native FFI | Build, app-runtime smoke, and the 1188-case correctness matrix | Release build on a physical iPhone (iOS 18.7): camera, shader display, and the device check |
| macOS | Native FFI | Example build, app-runtime smoke, and the 1188-case correctness matrix | Camera stream smoke with the built-in camera |
| Windows | Native FFI | Build, app-runtime smoke, and the 1188-case correctness matrix | — |
| Linux | Native FFI | Example build, packaging, app-runtime smoke, and the 1188-case correctness matrix | — |
| Web | WASM backend (JavaScript and `--wasm` builds); operation parity with native in checked cases | Package checks, browser tests, and the 1188-case correctness matrix on both builds | Chrome |

## Web backend

Web operations match the native backend in the checked cases on the JavaScript
and `--wasm` Flutter builds (verified in Chrome). `chromaSwap` is supported for
NV12 only, as on native. Safari and Firefox have not been verified.
`YuvFfi.initialize()` loads the module; use `YuvCapabilities` to query the
operations exported by that module.

## Migrating to 0.5.x

The compatibility declarations from 0.2.4 and retracted 0.4.0 were removed.
The detailed upgrade steps, API mapping, behavior changes, and verification
commands are in [MIGRATION.md](MIGRATION.md). Key points: initialize every
isolate, review mutating versus copy-returning calls, preserve plane layout
explicitly when needed, and migrate serialized frames through an
application-owned representation. The same guide applies to applications
whose lockfile still resolves 0.4.0.

## Building from a repository checkout

Native sources live in `src/` and are built through the platform plugin build
configuration. From a repository checkout, build the Web module from a
macOS/Linux shell, Git Bash, or WSL:

```sh
sh ./tool/wasm/build_wasm.sh
```

Do not edit `lib/src/functions/bindings/yuv_ffi_bingings.dart` manually.
Regenerate bindings after a header or configuration change:

```sh
dart run ffigen --config ffigen.yaml
```

## License

[MIT License](https://opensource.org/license/mit/)
