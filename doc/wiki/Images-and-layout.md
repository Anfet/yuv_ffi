# Images and layout

**Task:** choose a pixel format, create a `YuvImage` from RGBA bytes, from a decoded PNG or JPEG, or from plane buffers
you already own, and decide whether to keep or remove row padding.

**Conditions:** `YuvFfi.initialize()` has completed (see
[Getting started](https://github.com/Anfet/yuv_ffi/wiki/Getting-started)). Creating an empty image and reading its
planes works without it; converting RGBA bytes needs it.

## Formats

`YuvPixelFormat` has three stored formats. RGBA8888 is not one of them: it is only an input you convert from.

| Format | Planes | What each plane holds |
| --- | --- | --- |
| `YuvPixelFormat.i420` | 3: Y, U, V | Y has one byte per pixel. U and V have one byte per chroma sample each, in separate planes. |
| `YuvPixelFormat.nv12` | 2: Y, UV | Y as above. One chroma plane holds interleaved `(U, V)` byte pairs, so its `pixelStride` is 2. |
| `YuvPixelFormat.bgra8888` | 1 | Four bytes per pixel in B, G, R, A order. The only format with an alpha channel. |

In I420 and NV12 the chroma planes have one sample for every 2 by 2 block of pixels. Their size is rounded up: a 5 by 3
image has a 3 by 2 chroma grid. This is called 4:2:0 subsampling, and it is why cropping or patching such images
works on even coordinates (see [Processing and mutations](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations)).

Every `YuvPlane` describes how its bytes are laid out:

| Field | Meaning |
| --- | --- |
| `height` | Number of rows in the plane. |
| `rowStride` | Bytes from the start of one row to the start of the next. Larger than the visible row means padding at the end of each row. |
| `pixelStride` | Bytes from one sample to the next in a row. Larger than the sample size means a gap between samples. |
| `bytes` | The mutable storage: exactly `height * rowStride` bytes. |

## Create an image

| You have | Use |
| --- | --- |
| Nothing yet | `YuvImage.i420(w, h)`, `YuvImage.nv12(w, h)`, `YuvImage.bgra(w, h)` allocate zero-filled planes. `YuvImage.allocate(format, w, h)` does the same for a format chosen at run time and is always tightly packed. |
| RGBA bytes (`width * height * 4`) | `YuvImage.fromRgbaBytes(bytes, width: w, height: h, format: f)` allocates and converts. `image.applyRgbaBytes(bytes)` converts into an image you already have. |
| A PNG, JPEG or other encoded file | Decode it with Flutter first; see [Load a PNG or JPEG](#load-a-png-or-jpeg). |
| Plane buffers from a decoder or a camera | Pass them as `planes:` to a factory and choose a `layout:`; see [Packed or preserved layout](#packed-or-preserved-layout). |
| Bytes written by `encodeTo` | `YuvImage.decode(stream)`. This reads only the package's own container, not PNG or JPEG. |

Dimensions must be positive. Constructors throw `ArgumentError` for a zero or negative width or height.

### Look at the planes

This program allocates a 6 by 4 image in each format and prints the geometry of its planes.

```dart
import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  for (final format in YuvPixelFormat.values) {
    final image = YuvImage.allocate(format, 6, 4);
    debugPrint('${format.name} ${image.width}x${image.height}');
    for (final plane in image.planes) {
      debugPrint('  rows ${plane.height}, rowStride ${plane.rowStride}, pixelStride ${plane.pixelStride}');
    }
  }
}
```

Expected output:

```text
i420 6x4
  rows 4, rowStride 6, pixelStride 1
  rows 2, rowStride 3, pixelStride 1
  rows 2, rowStride 3, pixelStride 1
nv12 6x4
  rows 4, rowStride 6, pixelStride 1
  rows 2, rowStride 6, pixelStride 2
bgra8888 6x4
  rows 4, rowStride 24, pixelStride 4
```

The NV12 chroma row is as wide as the Y row: three chroma samples of two bytes each.

### Load a PNG or JPEG

`yuv_ffi` does not decode encoded image files. Let Flutter decode them to RGBA and convert the result. Call it after
`YuvFfi.initialize()`.

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yuv_ffi/yuv_ffi.dart';

/// Decodes PNG, JPEG or any other format Flutter can decode into a [YuvImage].
Future<YuvImage> yuvImageFromEncoded(Uint8List encoded, {YuvPixelFormat format = YuvPixelFormat.i420}) async {
  final codec = await ui.instantiateImageCodec(encoded);
  try {
    final frame = await codec.getNextFrame();
    final decoded = frame.image;
    try {
      final rgba = await decoded.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) {
        throw StateError('The decoded image has no pixel data.');
      }
      final bytes = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
      return YuvImage.fromRgbaBytes(bytes, width: decoded.width, height: decoded.height, format: format);
    } finally {
      decoded.dispose();
    }
  } finally {
    codec.dispose();
  }
}
```

Pass the file's bytes (from an asset, a file or a network response) and keep the result for as long as you need it.
I420 and NV12 have no alpha channel, so transparency is lost in them; use `YuvPixelFormat.bgra8888` to keep it. If
Flutter cannot decode the bytes, `instantiateImageCodec` throws and nothing is allocated.

## Packed or preserved layout

Planes you did not allocate yourself (from a camera, a video decoder or a platform API) often have padded rows or gaps
between samples. When you pass them to `YuvImage.i420`, `YuvImage.nv12` or `YuvImage.bgra` through `planes:`, the
`layout` argument decides what is stored:

| `layout` | What the image keeps | Use it when |
| --- | --- | --- |
| `YuvPlaneLayout.packed` (default) | Only the visible samples, copied into tight planes. Row padding and sample gaps are discarded. | You want a simple, predictable image and do not need the original strides. |
| `YuvPlaneLayout.preserve` | The strides, gaps and padding bytes exactly as supplied. | Strides matter later: you hand the planes back to another API, or you want to avoid a repacking pass. |

Both choices copy the bytes you pass, so you keep ownership of your own planes. `copy()`, `decode` and `applyPlanes`
always preserve the layout of the image they work on, and `YuvImage.allocate` always produces tight planes.

```dart
import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  // A 2x2 I420 image whose Y rows are padded to 4 bytes and whose chroma rows are padded to 2 bytes.
  List<YuvPlane> paddedPlanes() => <YuvPlane>[YuvPlane(2, 4), YuvPlane(1, 2), YuvPlane(1, 2)];

  final packed = YuvImage.i420(2, 2, planes: paddedPlanes());
  final kept = YuvImage.i420(2, 2, planes: paddedPlanes(), layout: YuvPlaneLayout.preserve);

  debugPrint('default (packed): rowStride ${packed.yPlane.rowStride}, tight ${packed.isTightlyPacked}');
  debugPrint('preserve: rowStride ${kept.yPlane.rowStride}, tight ${kept.isTightlyPacked}');

  kept.pack();
  debugPrint('after pack(): rowStride ${kept.yPlane.rowStride}, tight ${kept.isTightlyPacked}, revision ${kept.revision}');
}
```

Expected output:

```text
default (packed): rowStride 2, tight true
preserve: rowStride 4, tight false
after pack(): rowStride 2, tight true, revision 1
```

`pack()` removes the padding of an existing image in place and returns the image. It does nothing, and does not advance
the revision, when the image is already tight. The discarded padding cannot be recovered: call `copy()` first if you
need the padded original (`image.copy().pack()` leaves `image` untouched). After `pack()` or `applyPlanes`, plane
references you obtained earlier are stale; read `planes`, `yPlane`, `uPlane` and `vPlane` again.

NV12 is special: its packed chroma plane keeps `pixelStride` 2, because each sample is a `(U, V)` pair. Packing removes
only the row padding there, never the pair.

## Writing plane bytes yourself

`plane.bytes` is the live storage. You can fill it, but the image cannot see the change. After writing directly, call
`image.markDirty()`; otherwise a widget may keep showing an older cached frame. `apply*` calls and `applyPlanes` update
the revision for you. Writing a whole plane at once is also possible with `plane.assignFrom(bytes)`, which requires a
buffer of exactly the plane's length. Details on revisions are in
[Processing and mutations](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations#revisions-and-cache-keys).

## Limits and errors

| Symptom | Cause and action |
| --- | --- |
| `ArgumentError` mentioning `requires exactly 3 plane(s)` (or 2, or 1) | The number of planes does not match the format. I420 needs Y, U and V; NV12 needs Y and UV; BGRA needs one. |
| `ArgumentError` mentioning `Expected exactly N bytes` | A `YuvPlane` was created with `bytes` that are not `height * rowStride` long, or `assignFrom` got a buffer of a different length. A short buffer is rejected, not zero-padded. |
| `ArgumentError` mentioning `Row stride must be at least` | `rowStride` is too small for the plane's width and `pixelStride`. Increase it, or pass `bytes` and strides that describe the real buffer. |
| `ArgumentError` mentioning `Expected N rows` | The plane has the wrong number of rows. Chroma planes have `(height + 1) ~/ 2` rows. |
| `ArgumentError` about I420 U and V | The U and V planes must have the same `rowStride` and `pixelStride`. |
| `ArgumentError` about NV12 chroma pixel stride | A supplied NV12 chroma plane needs `pixelStride` 2. `YuvImage.nv12` also accepts a larger value as a gap between pairs; a smaller one is rejected. |
| `ArgumentError` about `bytes.length` of an RGBA buffer | The buffer is not exactly `width * height * 4` bytes. Check that you pass the decoded size, not the encoded file size. |
| A converted image looks swapped in red and blue | You passed BGRA bytes where RGBA is expected. `fromRgbaBytes` and `applyRgbaBytes` take R, G, B, A order; BGRA planes store B, G, R, A. |

## Related pages

- [Processing and mutations](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations): change or convert the image you built.
- [Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images): put it on screen.
- [Platforms and troubleshooting](https://github.com/Anfet/yuv_ffi/wiki/Platforms-and-troubleshooting): initialization and Web notes.
- [API reference](https://pub.dev/documentation/yuv_ffi/latest/): all parameters of `YuvImage`, `YuvPlane` and `YuvPlaneLayout`.
