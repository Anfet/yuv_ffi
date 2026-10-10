# yuv_ffi example

This runnable Flutter app demonstrates the current `yuv_ffi` API, including
image loading, transforms, and effects.

From this directory, install dependencies and start the app on a configured
device or desktop runner:

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

For Web, run `flutter run -d chrome`. Checked Web operation cases match native
on Flutter's JavaScript and `--wasm` builds in Chrome; `chromaSwap` supports
NV12 only. Safari and Firefox have not been verified. Android, iOS, macOS,
Windows, and Web runners are checked in here. A Linux runner is not included.
Camera capture and device checks are demonstrated by the separate `yuv_camera`
example. Image transforms can be explored by loading an image from the app bar.

For package setup, API migration, and platform/backend limitations, see the
[package README](../README.md).
