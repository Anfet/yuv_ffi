# Getting started

**Task:** show a processed image in a Flutter app: create it, crop and blur it, and put it on screen.

**Conditions:** a Flutter app on Dart 3.12 / Flutter 3.44 or later, targeting Android, iOS, macOS, Windows, Linux or Web
(see the README for the exact requirements). You have pixels in memory, not an encoded file; if your source is a PNG or
JPEG, decode it first as shown in [Images and layout](https://github.com/Anfet/yuv_ffi/wiki/Images-and-layout#load-a-png-or-jpeg).

This page is the shortest path to a result. The rest of the wiki explains each step in depth; the links at the end of
each step lead there.

## Step 1: add the package

```yaml
dependencies:
  yuv_ffi: ^0.5.2
```

Until 0.5.2 is published on pub.dev, resolve it from a local checkout with an ignored `pubspec_overrides.yaml` next to
your `pubspec.yaml` (do not commit it):

```yaml
dependency_overrides:
  yuv_ffi:
    path: ../yuv_ffi
```

Android needs `minSdk` 26 or higher. Nothing else has to be configured in your app.

## Step 2: write the app

This complete `lib/main.dart` builds an NV12 image from RGBA bytes, keeps its left half, blurs it and shows it.

```dart
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();

  const width = 320;
  const height = 180;
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      rgba[i] = 255 * x ~/ (width - 1); // red grows to the right
      rgba[i + 1] = 255 * y ~/ (height - 1); // green grows downwards
      rgba[i + 2] = 128; // blue
      rgba[i + 3] = 255; // alpha
    }
  }

  final image = YuvImage.fromRgbaBytes(rgba, width: width, height: height, format: YuvPixelFormat.nv12)
    ..applyCrop(Rect.fromLTWH(0, 0, width / 2, height.toDouble()))
    ..applyGaussianBlur(radius: 3, sigma: 2);

  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: YuvImageWidget(image: image)),
    ),
  );
}
```

What each part does:

- `YuvFfi.initialize()` loads the native library (or the Web module) and returns the capabilities of the loaded
  backend. Call it once per isolate before processing; see
  [Platforms and troubleshooting](https://github.com/Anfet/yuv_ffi/wiki/Platforms-and-troubleshooting).
- `YuvImage.fromRgbaBytes` allocates an image in the format you choose (here `YuvPixelFormat.nv12`) and converts the
  RGBA bytes into it. The buffer must hold exactly `width * height * 4` bytes. See
  [Images and layout](https://github.com/Anfet/yuv_ffi/wiki/Images-and-layout).
- `applyCrop` and `applyGaussianBlur` change the image in place and return the same image, so the cascade (`..`) works.
  Calls that start with `to`, plus `cropped`, `rotated` and `copy`, return a new image instead. See
  [Processing and mutations](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations).
- `YuvImageWidget` draws one image. For a stream of frames use a presenter instead; see
  [Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images).

## Expected result

A 160 by 180 picture appears in the middle of the window: the left half of the gradient, softly blurred. It is dark blue
at the top, becomes green towards the bottom, and gains some red towards its right edge. After the cascade
`image.width` is 160 and `image.height` is 180, because `applyCrop` replaced the image's size.

## Check what the backend can do

`initialize()` returns a `YuvCapabilities` snapshot. Ask it before choosing a path when the application must work with
every backend:

```dart
final capabilities = await YuvFfi.initialize();
final canBlur = capabilities.supports(YuvOperation.gaussianBlur, sourceFormat: YuvPixelFormat.nv12);
```

`supports` answers whether the operation exists for that format, not whether your arguments are valid; invalid
geometry still throws `ArgumentError`. A destination format is passed only for `YuvOperation.convert`.

## Limits and errors

| Symptom | Cause and action |
| --- | --- |
| `UnsupportedError` (on Web sometimes `StateError`) saying that `YuvFfi.initialize()` must complete or be called | A processing call such as `applyCrop` ran before `initialize()` finished. Await it first, in every isolate. |
| `ArgumentError` about `bytes.length` | The RGBA buffer is not exactly `width * height * 4` bytes. |
| The picture is a different size than expected | `applyCrop` and `applyRotation` replace the width and height of the image they are called on; read `image.width` after the call. |
| An operation fails on Web | On Web `initialize()` must be awaited before any `YuvImage` operation; there is no lazy fallback. See the Web section of the troubleshooting page. |

## Where to go next

- A stream of frames instead of one image: [Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images).
- Frames with padded rows or interleaved chroma: [Images and layout](https://github.com/Anfet/yuv_ffi/wiki/Images-and-layout).
- Boxes and marks over a frame: [Geometry and overlays](https://github.com/Anfet/yuv_ffi/wiki/Geometry-and-overlays).
- Camera capture: the [yuv_camera wiki](https://github.com/Anfet/yuv_camera/wiki).
