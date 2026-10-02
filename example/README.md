# yuv_ffi example

This runnable Flutter app demonstrates the current `yuv_ffi` API, including
camera previews, image transforms, effects, and face detection.

From this directory, install dependencies and start the app on a configured
device or desktop runner:

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

For Web, run `flutter run -d chrome`. Web uses the partial WASM backend; it does
not yet provide feature parity with the native backends. Android, iOS, macOS,
Windows, and Web runners are checked in here. A Linux runner is not included.

On the iOS Simulator, run the example with an iOS 18.x runtime or on a device:
`google_mlkit_face_detection` does not support arm64 on the iOS 26+ Simulator.

The camera preview needs a camera and permission to use it. Android and iOS ask
for camera access at runtime. On macOS and Windows, allow camera access in the
system privacy settings. In a browser, grant camera access to the site; Web
camera access requires HTTPS or localhost. Image transforms can be explored
without a camera by loading an image from the app bar.

The camera layer in `lib/camera/` exposes `YuvCameraFrameSource` and immutable
`YuvCameraFrame` deliveries. Import to `YuvImage` is lazy and shared by display,
processing, and capture. Android orientation follows the sensor/device formula
used by the ML Kit camera example and mirrors front-camera output. Desktop and
Web frames are upright and unmirrored. iOS is currently also treated as upright
and unmirrored; this rule has not yet been verified on a physical iOS device.

`YuvCameraView` renders through the shader presenter, exposes current geometry,
throttles independent `onFrame` processing, and captures the next frame that is
actually drawn. `YuvTransformView` is the synchronous transform variant. The
camera screen sends raw frames plus their rotation to ML Kit and maps upright
face boxes through the display geometry. Its speed button runs the blur stand
once per second. The current fallback runs that native operation on the UI
isolate (the image/native handle is not transferable); on Web `compute` would
also use the main thread, so a temporary preview pause is expected.

For package setup, API migration, and platform/backend limitations, see the
[package README](../README.md).
