# Geometry and overlays

**Task:** draw boxes, marks or hit areas over a displayed frame so they stay aligned when the frame is rotated, mirrored,
scaled or clipped, and cut out exactly the part of a frame that the user sees.

**Conditions:** you know the frame size, how the frame must be rotated or mirrored to appear upright (a
`YuvFrameOrientation`), and the size of the widget that shows it. For displaying the frame itself see
[Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images).

## Three coordinate spaces

`YuvFrameGeometry` keeps three spaces apart. Mixing them is the usual cause of misplaced overlays.

| Space | Origin of the numbers | Typical owner |
| --- | --- | --- |
| Source | Pixels of the frame as it arrived, before any rotation. | The frame itself (`YuvImage`). |
| Upright | Source pixels after `orientation.rotation` is applied, before mirroring. | Detectors such as ML Kit, when you give them the raw frame together with its rotation. |
| View | Logical pixels of the widget that shows the frame. | Your `CustomPaint`, gestures and layout. |

`YuvFrameOrientation(rotation:, mirrored:)` says what turns the source into an upright picture: `rotation` is the
clockwise rotation, `mirrored` flips it horizontally after the rotation. `YuvFrameFit.contain` shows the whole frame and
leaves unused space; `cover` fills the view and clips what does not fit. `alignment` places the frame inside the unused
space (centered by default).

| Matrix on `YuvFrameGeometry` | Maps |
| --- | --- |
| `sourceToView` | A point of the source frame to the view. |
| `uprightToView` | A point of the upright frame (for example a detector's bounding box) to the view. |
| `viewToSource` | A touch or pointer position in the view back to the source frame. |

`destinationRect` is where the upright frame is drawn in the view, and `visibleSourceRect` is the part of the source that
is visible (smaller than the frame with `cover`).

## Map a box to the view

This program builds a geometry for a 640 by 480 frame that must be rotated 90 degrees clockwise and mirrored, shown with
`contain` in a 400 by 400 view, and maps a box that a detector reported in upright coordinates. It does not need
`YuvFfi.initialize()`.

```dart
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show MatrixUtils;
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  final geometry = YuvFrameGeometry(
    sourceSize: const Size(640, 480),
    viewSize: const Size(400, 400),
    orientation: const YuvFrameOrientation(rotation: YuvImageRotation.rotation90, mirrored: true),
    fit: YuvFrameFit.contain,
  );

  const box = Rect.fromLTWH(48, 64, 160, 160); // upright coordinates: 480 wide, 640 high
  debugPrint('frame drawn at ${geometry.destinationRect}');
  debugPrint('box in the view: ${MatrixUtils.transformRect(geometry.uprightToView, box)}');
}
```

Expected output:

```text
frame drawn at Rect.fromLTRB(50.0, 0.0, 350.0, 400.0)
box in the view: Rect.fromLTRB(220.0, 40.0, 320.0, 140.0)
```

The upright frame is 480 by 640. Contain scales it by 0.625 to 300 by 400 and centers it horizontally, so it starts at
x = 50. Mirroring then flips x inside that rectangle, which is why the box that started at x = 48 ends at the right.

## Overlay on a live view

`YuvFrameView` reports the geometry of what it draws through `onGeometryChanged`. Use that object for every overlay so
the overlay and the picture always share one mapping. This page shows a frame that needs rotation and mirroring, draws a
box defined in upright coordinates on top of it, and keeps them aligned when the window is resized.

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const MaterialApp(home: OverlayPage()));
}

class OverlayPage extends StatefulWidget {
  const OverlayPage({super.key});

  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<OverlayPage> {
  static const _orientation = YuvFrameOrientation(rotation: YuvImageRotation.rotation90, mirrored: true);
  static const _box = Rect.fromLTWH(48, 64, 160, 160); // a detector result in upright coordinates

  final YuvFramePresenter _presenter = YuvFramePresenter();
  YuvFrameGeometry? _geometry;

  @override
  void initState() {
    super.initState();
    const width = 640;
    const height = 480;
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        rgba[i] = x * 255 ~/ (width - 1);
        rgba[i + 1] = y * 255 ~/ (height - 1);
        rgba[i + 2] = 96;
        rgba[i + 3] = 255;
      }
    }
    final frame = YuvImage.fromRgbaBytes(rgba, width: width, height: height, format: YuvPixelFormat.nv12);
    _presenter.present(frame, orientation: _orientation);
  }

  @override
  void dispose() {
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          YuvFrameView(presenter: _presenter, fit: YuvFrameFit.contain, onGeometryChanged: (geometry) => setState(() => _geometry = geometry)),
          if (geometry != null) CustomPaint(painter: _BoxPainter(geometry, _box)),
        ],
      ),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.geometry, this.box);

  final YuvFrameGeometry geometry;
  final Rect box;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = MatrixUtils.transformRect(geometry.uprightToView, box);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF00FF00),
    );
  }

  @override
  bool shouldRepaint(_BoxPainter oldDelegate) => oldDelegate.geometry != geometry || oldDelegate.box != box;
}
```

Expected result: the gradient appears rotated a quarter turn clockwise and mirrored, fitted into the window, with a green
square outline over the same part of the picture whatever the window size. The outline is missing for the first moments:
the geometry arrives after the first frame has been decoded and laid out.

The same pattern applies to detector output. Give the detector the raw frame together with `orientation.rotation`, take
its boxes (they are in upright coordinates) and map each with `MatrixUtils.transformRect(geometry.uprightToView, box)`.
`yuv_ffi` does not depend on ML Kit; the wiring is application code, see the
[Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing) page of the yuv_camera wiki.

Other mappings use the same object. Use `geometry.sourceToView` for a point you know in raw frame pixels, and
`MatrixUtils.transformPoint(geometry.viewToSource, position)` to turn a tap position into a pixel of the source frame.

## Cut out what the user sees

`geometry.apply(frame)` returns a new image that contains only the visible part of the frame, with the rotation and the
mirror applied. If the frame has no visible area, `apply` throws `StateError` (`no visible source area`) because a
`YuvImage` cannot represent an empty image. This program computes a visible crop for a 640 by 480 frame in a 300 by 300
view with `cover`.

```dart
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  await YuvFfi.initialize();

  final frame = YuvImage.allocate(YuvPixelFormat.i420, 640, 480);
  final geometry = YuvFrameGeometry(
    sourceSize: const Size(640, 480),
    viewSize: const Size(300, 300),
    orientation: const YuvFrameOrientation(rotation: YuvImageRotation.rotation90, mirrored: true),
    fit: YuvFrameFit.cover,
  );

  final visible = geometry.apply(frame);
  debugPrint('visible area of the source: ${geometry.visibleSourceRect}');
  debugPrint('result: ${visible.width}x${visible.height}, source frame untouched: ${frame.width}x${frame.height}');
}
```

Expected output:

```text
visible area of the source: Rect.fromLTRB(80.0, 0.0, 560.0, 480.0)
result: 480x480, source frame untouched: 640x480
```

The upright frame (480 by 640) is scaled by 0.625 to 300 by 400, so `cover` clips 50 view pixels at the top and at the
bottom. 50 view pixels are 80 pixels of the upright frame, and the top and bottom edges of the upright frame are the
left and right edges of the source, so source columns 80 to 560 remain. The cut-out is rotated and mirrored, so it is 480 by 480.

## Limits and errors

| Symptom | Check and action |
| --- | --- |
| The overlay is mirrored or rotated against the picture | You mapped upright coordinates with `sourceToView`, or source coordinates with `uprightToView`. Detector boxes given the raw frame plus rotation are upright: use `uprightToView`. |
| The overlay is aligned for some device orientations only | The orientation you gave the detector differs from the one you gave `present` or `YuvFrameGeometry`. Use the same `YuvFrameOrientation` for both. |
| `ArgumentError`: `sourceSize and viewSize must be positive` | A size is zero, for example a view that has not been laid out yet. Build the geometry in `LayoutBuilder` once the constraints are positive, or use the object from `onGeometryChanged`. |
| `ArgumentError` about `source` and `sourceSize` | `geometry.apply(frame)` was given a frame whose size differs from `sourceSize`. Create the geometry from that frame's size. |
| The cut-out colors differ slightly from the screen | `apply` is a data operation, not a screenshot. For 4:2:0 frames an odd crop size or origin recomputes chroma from 2 by 2 pixel blocks. |
| The overlay is missing for the first frame | `onGeometryChanged` runs after the first frame has been decoded and laid out. Draw the overlay only once you have the geometry. |
| The overlay is drawn outside the visible area with `cover` | `cover` clips the frame to the view, but your painter can still draw anywhere. Test points against `geometry.visibleSourceRect` (source space) or clip the overlay. |

## Related pages

- [Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images): presenter, view and shader path.
- [Processing and mutations](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations): `cropped` and `rotated`.
- [Frame processing](https://github.com/Anfet/yuv_camera/wiki/Frame-processing) and
  [Geometry and overlays](https://github.com/Anfet/yuv_camera/wiki/Geometry-and-overlays) in the yuv_camera wiki.
