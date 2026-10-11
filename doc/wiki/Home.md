# yuv_ffi wiki

`yuv_ffi` creates, converts, transforms and displays raw YUV (I420, NV12) and BGRA images in Flutter. It works on decoded
pixels, not on encoded files: native platforms run C code through FFI, and Web runs a WASM backend. These guides give
step-by-step recipes, explain the behavior behind them and list the errors you are most likely to meet. The
[README](https://github.com/Anfet/yuv_ffi#readme) is the quick start, the
[API reference](https://pub.dev/documentation/yuv_ffi/latest/) lists every parameter, and the
[CHANGELOG](https://github.com/Anfet/yuv_ffi/blob/main/CHANGELOG.md) records what changed in each version.

**Documented version: 0.5.2.** This wiki describes `yuv_ffi` 0.5.2; every recipe here was built against that version.

Camera capture is not part of this package. For a live camera preview, frame processing and capture, use
[`yuv_camera`](https://github.com/Anfet/yuv_camera), which builds on `yuv_ffi`; its guides are in the
[yuv_camera wiki](https://github.com/Anfet/yuv_camera/wiki).

## Choose a route

### First result

You want to see a processed image on screen as fast as possible.

1. [Getting started](https://github.com/Anfet/yuv_ffi/wiki/Getting-started): add the package, initialize it, create
   an image, process it and show it.
2. [Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images): choose between a still image and a
   live stream of frames.

### Typical scenario

Your app receives decoded frames or pixel buffers, converts and edits them, and shows the latest result.

1. [Images and layout](https://github.com/Anfet/yuv_ffi/wiki/Images-and-layout): formats, planes, strides and when to
   keep or remove padding.
2. [Processing and mutations](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations): which calls change an
   image and which return a new one; crop, rotate, blur and format conversion.
3. [Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images): `YuvImageWidget` for one image,
   `YuvFramePresenter` and `YuvFrameView` for a stream.
4. [Geometry and overlays](https://github.com/Anfet/yuv_ffi/wiki/Geometry-and-overlays): draw boxes and marks that
   stay aligned with a rotated or mirrored frame.
5. [Platforms and troubleshooting](https://github.com/Anfet/yuv_ffi/wiki/Platforms-and-troubleshooting): per-isolate
   initialization, platform and Web limits, and fixes for common failures.

## All guides

| Guide | Use it to |
| --- | --- |
| [Getting started](https://github.com/Anfet/yuv_ffi/wiki/Getting-started) | Get a first image on screen and learn the three rules everything else builds on. |
| [Images and layout](https://github.com/Anfet/yuv_ffi/wiki/Images-and-layout) | Pick a format, build an image from RGBA bytes or from planes, and control strides and padding. |
| [Processing and mutations](https://github.com/Anfet/yuv_ffi/wiki/Processing-and-mutations) | Crop, rotate, flip, blur and convert images; understand `apply*` versus returned copies and `revision`. |
| [Displaying images](https://github.com/Anfet/yuv_ffi/wiki/Displaying-images) | Show a still image or a stream of frames; understand the shader path, its fallback and `dispose`. |
| [Geometry and overlays](https://github.com/Anfet/yuv_ffi/wiki/Geometry-and-overlays) | Map points between source, upright and view coordinates; cut out the visible area. |
| [Platforms and troubleshooting](https://github.com/Anfet/yuv_ffi/wiki/Platforms-and-troubleshooting) | Initialize in every isolate, read the platform notes, and fix load, native and Web errors. |

## Related

- [Migration guide](https://github.com/Anfet/yuv_ffi/blob/main/MIGRATION.md) for applications moving from 0.2.4 or
  the retracted 0.4.0.
- [Web parity evidence](https://github.com/Anfet/yuv_ffi/blob/main/doc/web-parity.md) for the exact cases checked on
  Web.
- [Example app](https://github.com/Anfet/yuv_ffi/tree/main/example): image loading, transforms, effects and frame
  display.
- [yuv_camera wiki](https://github.com/Anfet/yuv_camera/wiki): camera preview, frame processing and capture.
