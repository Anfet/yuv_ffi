# Processing and mutations

**Task:** change an image (crop, rotate, flip, blur, adjust colors, convert the format) and know exactly which calls
change the image you hold and which give you a new one.

**Conditions:** `YuvFfi.initialize()` has completed in the isolate that runs the calls; see
[Platforms and troubleshooting](https://github.com/Anfet/yuv_ffi/wiki/Platforms-and-troubleshooting). On native
platforms constructors, plane access, `copy`, `applyPlanes`, `applyPatch` and the byte getters work without it; every
other processing call throws `UnsupportedError` until it has finished. On Web every `YuvImage` operation needs it.

## Kinds of calls

| Family | Calls | What happens |
| --- | --- | --- |
| In place (`apply*`) | `applyRgbaBytes`, `applyGrayscale`, `applyBlackWhite`, `applyNegate`, `applyGaussianBlur`, `applyMeanBlur`, `applyBoxBlur`, `applyCrop`, `applyFlipHorizontal`, `applyFlipVertical`, `applyRotation`, `applyFormat`, `applyChromaSwap`, `applyPlanes`, `applyPatch` | The receiver changes and the same object is returned, so calls chain with `..`. |
| New image | `copy`, `cropped`, `rotated`, `toI420`, `toNv12`, `toBgra`, `YuvImage.decode`, `YuvImage.fromRgbaBytes` | The receiver is never changed. The result is independent; it never shares bytes with the source, even for a same-format `toBgra()` or `rotated(YuvImageRotation.rotation0)`, which return copies. |
| Bytes only | `toBytes`, `toBgraBytes`, `toImage` | Return all plane storage including padding (`toBytes`), tight `width * height * 4` BGRA pixels (`toBgraBytes`) or a Flutter `ui.Image` (`toImage`); the image is not changed. |

A successful `apply*` call advances `image.revision` exactly once. A rejected call changes nothing: not the bytes, the
format, the size or the revision. A call that genuinely changes nothing (for example `applyRotation(rotation0)`, a crop
that selects no pixels, a blur with radius 0, or `applyFormat` to the format the image already has) leaves the revision
alone as well.

### Revisions and cache keys

`revision` is how widgets know an image changed. `YuvImageProvider` (used by `YuvImageWidget`) builds its cache key from
the image identity and its revision. Two consequences:

- Mutate through the API and the revision moves by itself.
- Write into `plane.bytes` (or call `plane.setPixel` or `plane.assignFrom`) and the image cannot notice; call
  `image.markDirty()` afterwards so the next widget build decodes the new content.

### Keep the original, change a copy

This program applies one of each kind of call and prints what happened to the original.

```dart
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  await YuvFfi.initialize();

  final original = YuvImage.allocate(YuvPixelFormat.i420, 320, 180);
  final start = original.revision;

  final rotated = original.rotated(YuvImageRotation.rotation90); // a new image
  debugPrint('rotated ${rotated.width}x${rotated.height}; original ${original.width}x${original.height}, revision +${original.revision - start}');

  final blurred = original.copy().applyGaussianBlur(radius: 2, sigma: 2); // changes only the copy
  debugPrint('blurred copy revision ${blurred.revision}; original revision +${original.revision - start}');

  final same = original.applyCrop(const Rect.fromLTWH(10, 10, 100, 50)); // changes the original
  debugPrint('cropped: ${original.width}x${original.height}, same object ${identical(same, original)}, revision +${original.revision - start}');

  original.applyCrop(Rect.zero); // selects no pixels
  debugPrint('empty crop: revision +${original.revision - start}');
}
```

Expected output:

```text
rotated 180x320; original 320x180, revision +0
blurred copy revision 1; original revision +0
cropped: 100x50, same object true, revision +1
empty crop: revision +1
```

Use `copy()` whenever more than one place holds the same image. Frames that a camera or another producer hands to you
usually must not be changed; see the [yuv_camera wiki](https://github.com/Anfet/yuv_camera/wiki).

## Operations

### Crop

`applyCrop(region)` and `cropped(region)` take a `Rect` in image pixels. Its left and top edges are rounded down, its
right and bottom edges are rounded up, and the result is clamped to the image. A region that selects no pixels is a
no-op for `applyCrop`, and `cropped` returns an independent copy of the whole image in that case. In I420 and NV12
an odd crop size or origin recomputes chroma from 2 by 2 pixel blocks, so the colors of the result can differ from the
source pixels.

### Rotate and flip

`applyRotation(YuvImageRotation.rotation90)` and `rotated(...)` rotate clockwise by 0, 90, 180 or 270 degrees. A
rotation by 90 or 270 swaps width and height. `applyFlipHorizontal` and `applyFlipVertical` mirror in place and keep the
size.

### Blur

| Call | Parameters |
| --- | --- |
| `applyGaussianBlur(radius:, sigma:)` | `sigma` must be finite and positive when `radius` is not 0. |
| `applyMeanBlur(radius:, region:)` | `region` (optional) is in image pixels, rounded outward and clamped; `null` blurs the whole image. |
| `applyBoxBlur(radius:, region:)` | Same arguments as the mean blur, with a normalized box kernel. |

A `radius` of 0 is a no-op; a negative radius or one above 256 throws `ArgumentError`. A `region` that selects no pixels
blurs nothing; it does not fall back to the whole image.

### Colors

`applyGrayscale`, `applyBlackWhite` (a black/white threshold effect) and `applyNegate` change the colors in place in any
of the three formats.

### Convert the format

| Call | Result |
| --- | --- |
| `applyFormat(format)` | Converts this image to `format` in place. Converting to the current format is a no-op. |
| `toI420()`, `toNv12()`, `toBgra()` | A new image in that format. If the image already has it, you get an independent copy. |

Conversions between YUV and BGRA use the BT.601 matrix in limited (video) range; the package does not detect full-range
data or another color matrix and has no option to select one.
| `applyChromaSwap()` | Swaps the U and V sample values of an NV12 image and keeps it labeled NV12. Throws `UnsupportedError` for I420 and BGRA, without changing the image. |

All nine format pairs (I420, NV12 and BGRA, each to each) are supported on native and Web in the cases the
[Web parity evidence](https://github.com/Anfet/yuv_ffi/blob/main/doc/web-parity.md) records.

### Paste a patch

`applyPatch(fragment, x:, y:)` copies an opaque image of the same format into this one without scaling. It never touches
the destination's padding bytes. On native platforms it works without `initialize()` because it is plain Dart, so
the program below does not call it; on Web await `YuvFfi.initialize()` first, as for every `YuvImage` operation.

```dart
import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  final destination = YuvImage.allocate(YuvPixelFormat.i420, 8, 8);
  final fragment = YuvImage.allocate(YuvPixelFormat.i420, 4, 4);
  fragment.yPlane.bytes.fillRange(0, fragment.yPlane.bytes.length, 255);

  final start = destination.revision;
  destination.applyPatch(fragment, x: 2, y: 2);
  debugPrint(
    'patched: revision +${destination.revision - start}, top-left Y ${destination.yPlane.getPixel(0, 0)}, patch Y ${destination.yPlane.getPixel(2, 2)}',
  );

  try {
    destination.applyPatch(fragment, x: 3, y: 2);
  } on ArgumentError catch (error) {
    debugPrint('rejected: ${error.message}; revision +${destination.revision - start}');
  }
}
```

Expected output:

```text
patched: revision +1, top-left Y 0, patch Y 255
rejected: YUV patch coordinates must follow chroma 2x2 alignment; revision +1
```

The rules: both images have the same format; the fragment must fit completely and be a different image that shares no
bytes with the destination; for I420 and NV12 `x` and `y` must be even, and an odd fragment width or height is accepted
only when it reaches the right or bottom edge. A rejected patch leaves the destination unchanged.

## Limits and errors

| Symptom | Check and action |
| --- | --- |
| `UnsupportedError` saying `YuvFfi.initialize() must complete` | The call is capability-gated and ran before initialization finished in this isolate. Await `YuvFfi.initialize()` there. |
| `UnsupportedError` for `applyChromaSwap` | The image is not NV12. Convert first (`image.applyFormat(YuvPixelFormat.nv12).applyChromaSwap()`) or skip the swap. |
| `UnsupportedError` naming an operation and formats | The loaded backend does not export that operation. Query `capabilities.supports(...)` after `initialize()` and choose another path. |
| `ArgumentError` about `radius` | The radius is negative or above 256. Use 0 to skip, or 1 to 256. |
| `YuvNativeException` | The native side reported an overflow, an allocation failure or an internal error. It carries `statusCode` and the `operation`; the image keeps its previous bytes, size and revision. Reduce the size or retry; report it with the status code if it repeats. |
| The widget shows the old picture after a change | You wrote into `plane.bytes` without `markDirty()`, or you did not rebuild the widget after an `apply*` call. See [Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images). |
| A patch is rejected with an alignment message | `x`, `y` or an odd fragment extent breaks 2 by 2 chroma alignment. Use even coordinates, or let an odd extent end at the image edge. |

## Related pages

- [Images and layout](https://github.com/Anfet/yuv_ffi/wiki/Images-and-layout): formats, planes and padding.
- [Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images): show the result.
- [Geometry and overlays](https://github.com/Anfet/yuv_ffi/wiki/Geometry-and-overlays): crop and orient exactly what is visible.
- [API reference](https://pub.dev/documentation/yuv_ffi/latest/): every parameter of `YuvImage`.
