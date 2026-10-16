# Displaying images

**Task:** put a `YuvImage` on screen: either one still image, or a live stream of frames where only the newest frame
matters.

**Conditions:** `YuvFfi.initialize()` has completed; the image is in memory (see
[Images and layout](https://github.com/Anfet/yuv_ffi/wiki/Images-and-layout)). For frames that come from a camera,
`yuv_camera` already wires a presenter for you; see the [yuv_camera wiki](https://github.com/Anfet/yuv_camera/wiki).

## Which widget

| You show | Use | Why |
| --- | --- | --- |
| One image that changes rarely (a photo, an editor canvas) | `YuvImageWidget` | It behaves like Flutter's `Image` and goes through the image cache. |
| A stream of frames (video, animation, a processing loop) | `YuvFramePresenter` with `YuvFrameView` | It keeps one frame in flight, drops frames that arrive too early and never fills the image cache. |
| Your own `Image` widget or `DecorationImage` | `YuvImageProvider(image)` | It is the `ImageProvider` behind `YuvImageWidget`. |

## Show a still image

`YuvImageWidget(image: image)` draws the image at its own pixel size (`BoxFit.none`). Put it in a bounded space and pass
`boxFit` to scale it. The widget creates a new `YuvImageProvider` on every build, and the provider's cache key is the
image identity plus its revision when the provider was created. So after you change the image, rebuild the widget
(`setState`) and it shows the new content; without a rebuild it keeps the old picture.

This app shows an image and rotates it by 90 degrees each time you tap the button.

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const MaterialApp(home: RotatingImagePage()));
}

class RotatingImagePage extends StatefulWidget {
  const RotatingImagePage({super.key});

  @override
  State<RotatingImagePage> createState() => _RotatingImagePageState();
}

class _RotatingImagePageState extends State<RotatingImagePage> {
  late final YuvImage _image = _buildImage();

  static YuvImage _buildImage() {
    const width = 240;
    const height = 120;
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        rgba[i] = x * 255 ~/ (width - 1);
        rgba[i + 1] = y * 255 ~/ (height - 1);
        rgba[i + 2] = 64;
        rgba[i + 3] = 255;
      }
    }
    return YuvImage.fromRgbaBytes(rgba, width: width, height: height, format: YuvPixelFormat.i420);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: YuvImageWidget(image: _image, boxFit: BoxFit.contain),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _image.applyRotation(YuvImageRotation.rotation90)),
        child: const Icon(Icons.rotate_right),
      ),
    );
  }
}
```

Expected result: the gradient is shown wide, scaled to fit a 300 by 300 box. Each tap rotates it a quarter turn clockwise;
it becomes tall (120 by 240 pixels), then wide again.

For decoded images, `YuvImageWidget.boxFit` defaults to `BoxFit.none`; pass `BoxFit.contain` when the image should fit
inside its box. `YuvFrameView.fit` defaults to `YuvFrameFit.contain`, so use the explicit decoded-image setting when
you want both display paths to show the full frame.

Things to know:

- `YuvImageProvider` takes its own copy of the image when decoding starts, so you may change or reuse the image right
  after handing it to the widget; the frame already queued for display does not change.
- A provider only decodes the frame it was created for. If the image is changed between creating a provider and its
  first load, loading fails with a `StateError` that tells you to create a new provider. `YuvImageWidget` avoids this by
  creating one on every build; if you hold providers yourself, create a new one after each change.
- A class that implements `YuvImage` outside this package does not report revisions, so each of its providers gets its
  own cache key and is converted again on every rebuild. That costs time but never shows a wrong frame.

## Show a stream of frames

A `YuvFramePresenter` shows one frame at a time:

- `present(frame)` starts showing a frame and returns `true`. It returns `false`, and drops that frame, while the
  previous frame is still being decoded and drawn, and after `dispose()`. Under load intermediate frames are skipped and
  the screen always shows the newest frame that finished.
- The frame is copied before `present` returns, so you may overwrite and reuse the same `YuvImage` for the next frame.
- `onFramePresented` fires once per frame that was actually drawn, so a rate computed from it is the display rate, not
  the arrival rate.
- `YuvFrameView(presenter: ...)` draws the current frame, and nothing before the first one. Its default fit is
  `YuvFrameFit.contain`; select `cover` explicitly to crop. `onGeometryChanged` runs after a frame has a non-zero, finite
  viewport layout and is not called before the first frame or for a zero/non-finite viewport.

This app produces a new 160 by 90 frame about every 33 ms into one reused image, presents it, and counts the frames the
presenter dropped.

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YuvFfi.initialize();
  runApp(const MaterialApp(home: LiveFramesPage()));
}

class LiveFramesPage extends StatefulWidget {
  const LiveFramesPage({super.key});

  @override
  State<LiveFramesPage> createState() => _LiveFramesPageState();
}

class _LiveFramesPageState extends State<LiveFramesPage> {
  static const _width = 160;
  static const _height = 90;

  final YuvFramePresenter _presenter = YuvFramePresenter();
  final YuvImage _frame = YuvImage.allocate(YuvPixelFormat.nv12, _width, _height);
  final Uint8List _rgba = Uint8List(_width * _height * 4);
  Timer? _timer;
  int _tick = 0;
  int _dropped = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _produce());
  }

  void _produce() {
    _tick++;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        final i = (y * _width + x) * 4;
        _rgba[i] = (x * 2 + _tick * 4) & 0xFF;
        _rgba[i + 1] = y * 255 ~/ (_height - 1);
        _rgba[i + 2] = 96;
        _rgba[i + 3] = 255;
      }
    }
    _frame.applyRgbaBytes(_rgba);
    if (!_presenter.present(_frame)) {
      setState(() => _dropped++);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: YuvFrameView(presenter: _presenter, fit: YuvFrameFit.contain),
          ),
          Padding(padding: const EdgeInsets.all(8), child: Text('Dropped frames: $_dropped')),
        ],
      ),
    );
  }
}
```

Expected result: a gradient whose red channel scrolls continuously, and a counter of dropped frames. The counter grows
only when a frame arrives while the previous one is still being decoded or waiting to be drawn; on a fast device it may
stay at 0. Either way the frame you see is the newest one that finished.

### Lifecycle and dispose

| Object | Who owns it | What you must do |
| --- | --- | --- |
| The `YuvImage` you pass to `present` | You | Nothing special: the presenter copies it. Reuse or mutate it freely afterwards. |
| The `ui.Image` in `presenter.image` | The presenter | Do not dispose it. Call `clone()` if you need it beyond the next `present`, `reset` or `dispose`. |
| The `YuvFramePresenter` | You | Call `dispose()` when the stream ends and when the widget that created it is disposed. After `dispose()`, `present` returns `false`. |

`reset()` drops the frame on screen and any frame in flight; use it when you replace the stream behind the same
presenter. A decode that was still running for an earlier frame is discarded and never reaches the screen or
`onFramePresented`; the presenter stays busy until that decode ends, so a new stream never has two frames in flight.

## Shader path and fallback

By default the presenter converts each frame to BGRA bytes and decodes them. Pass `useShader: true` to upload the YUV
planes themselves and convert them on the GPU:

```dart
final presenter = YuvFramePresenter(useShader: true);
```

The shader loads asynchronously. Until it has loaded, or when the platform cannot provide it, frames use the BGRA path;
`presenter.hasShader` tells you which one is active. With the shader enabled, `presenter.image` is always `null`.

Even with a loaded shader a frame uses the BGRA path when its layout cannot be uploaded: a Y plane with `pixelStride`
other than 1, I420 chroma planes whose U and V strides differ or are neither 1 nor 2, NV12 chroma with a `pixelStride`
other than 2,
a packed texture larger than 4096 texels in either dimension, or a BGRA frame (which needs no conversion). The result
on screen is pixel-equivalent; only the work moves. The shader uses the same BT.601 limited-range formula as the
format conversions and does not detect another range or color matrix. On Web the shader packs three bytes per texel (alpha stays opaque)
because CanvasKit premultiplies sampled colors; this is why the Web results are checked separately in the
[Web parity evidence](https://github.com/Anfet/yuv_ffi/blob/main/doc/web-parity.md).

For custom painting, `YuvFrameRenderer.load()`, `upload(frame)` and `paint(canvas, texture, geometry)` expose the same
mechanism; see the [API reference](https://pub.dev/documentation/yuv_ffi/latest/). Most apps use the presenter.

Frames can also be rotated or mirrored at draw time, without producing a new image: pass
`orientation: YuvFrameOrientation(...)` to `present`. See
[Geometry and overlays](https://github.com/Anfet/yuv_ffi/wiki/Geometry-and-overlays).

## Limits and errors

| Symptom | Check and action |
| --- | --- |
| `YuvFrameView` stays empty | Nothing has been drawn yet. Check that `present` returned `true`, that the presenter was not disposed, and that `FlutterError.onError` did not report an error whose context is `decoding a preview frame` or `uploading a preview frame`; decode errors are reported there, not thrown. |
| `present` often returns `false` | A frame is still in flight. This is the designed drop behavior; check `presenter.isBusy`, and lower the rate you present at if you need every frame. If it returns `false` for good, the presenter was disposed. |
| Synchronous exception from `present` | Copying or converting the frame failed, for example because the frame is invalid. The presenter is free again and the next frame can be presented. |
| `hasShader` is `false` with `useShader: true` | The shader asset is still loading, or it could not be loaded. Frames are shown through the BGRA path meanwhile. |
| `StateError` about creating a new provider | A `YuvImageProvider` was created for an older revision of an image that was changed afterwards. Create a new provider (or rebuild `YuvImageWidget`) after every change. |
| The picture does not update after a change | For a still image: rebuild the widget. For a stream: call `present` with the new frame. If you wrote into `plane.bytes`, call `markDirty()` first. |
| A kept `ui.Image` is disposed | You held `presenter.image` past the next frame. Take `clone()` instead of keeping the original. |

## Related pages

- [Images and layout](https://github.com/Anfet/yuv_ffi/wiki/Images-and-layout): what the frames you present look like.
- [Geometry and overlays](https://github.com/Anfet/yuv_ffi/wiki/Geometry-and-overlays): placement, rotation and overlays.
- [Platforms and troubleshooting](https://github.com/Anfet/yuv_ffi/wiki/Platforms-and-troubleshooting): initialization and Web.
- [yuv_camera wiki](https://github.com/Anfet/yuv_camera/wiki): a ready-made live camera preview built on the presenter.
