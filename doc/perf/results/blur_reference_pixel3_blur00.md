# BLUR-00: public Dart blur baseline on Pixel 3

Date: 2026-09-26. Device: Google Pixel 3 `8B1X11QLW`, Android 12
(`google/blueline/blueline:12/SP1A.210812.016.C1/8029091:user/release-keys`).
The temporary application `com.yuvffi.bench.blur_runner` was built as Android
Release/AOT and installed only with `adb install -r`. No power-plan setting or
device user data was changed.

## Input and timing contract

The source is `tool/bench/fixtures/blur_reference_1477x1065.png`, PNG SHA-256
`7c36de007e221a60403fb2a17f5bbc40c8f410a8f1e74fe67ff851503825c600`.
The second input is exactly `copyCrop(x: 0, y: 163, width: 1476, height: 738)`
followed by `copyResize(width: 720, height: 360, Interpolation.linear)` from
`package:image`.

The runner calls public `YuvImage.nv21(...).applyRgbaBytes(...)` once during
setup. In this package that legacy constructor selects a packed `Y + UV`
layout and reports `format == nv12`; each record therefore labels the selected
fixture order as `UV`. This is a deterministic PNG conversion, not a claim
about a raw CameraX buffer or its format label.

PNG decode, RGBA-to-package conversion, and `source.copy()` happen before each
timer. A timer covers exactly one public `applyBoxBlur`, `applyMeanBlur`, or
`applyGaussianBlur` call, including its Dart transport and the current native
RGB/YUV conversion path. There are two warmups and seven recorded samples per
operation and size. Radius is 10; Gaussian sigma is 10.

## Results

Times are milliseconds. Spread is `max - min` over the seven recorded calls.

| Operation | Input | Source SHA-256 | Result SHA-256 | Raw samples | Median | Spread |
| --- | --- | --- | --- | --- | ---: | ---: |
| Box | 1477x1065 | `09ab1306d279f6b79bcc77dced485bc2d0691cf823aad82c0b5b1ad6f041cc78` | `a2639e9ade7ff9231ee2fdb604a378af1cf6f1c0a0ea74d36fe23d50a166316d` | 55.013, 53.481, 54.943, 53.601, 55.008, 53.397, 55.093 | 54.943 | 1.696 |
| Box | 720x360 | `1fada775114bc0f90a9fb1338acdfd302c281331598400c328fde897106a289e` | `08dbafe5fa0ecfa28ef5e01704c053ac876dfd979f3a88708101261707123f48` | 8.535, 9.067, 8.540, 8.518, 9.047, 8.562, 8.564 | 8.562 | 0.549 |
| Mean | 1477x1065 | `09ab1306d279f6b79bcc77dced485bc2d0691cf823aad82c0b5b1ad6f041cc78` | `a2639e9ade7ff9231ee2fdb604a378af1cf6f1c0a0ea74d36fe23d50a166316d` | 54.504, 52.894, 54.561, 53.109, 54.374, 52.832, 54.375 | 54.374 | 1.729 |
| Mean | 720x360 | `1fada775114bc0f90a9fb1338acdfd302c281331598400c328fde897106a289e` | `08dbafe5fa0ecfa28ef5e01704c053ac876dfd979f3a88708101261707123f48` | 8.683, 9.136, 8.635, 8.637, 9.042, 8.626, 8.644 | 8.644 | 0.510 |
| Gaussian | 1477x1065 | `09ab1306d279f6b79bcc77dced485bc2d0691cf823aad82c0b5b1ad6f041cc78` | `6a086b28397774e523b9ad30edaa531d75a37d275ef8479be6e58b7d742d8f09` | 1429.546, 1428.029, 1430.591, 1427.216, 1369.141, 1363.857, 1378.691 | 1427.216 | 66.734 |
| Gaussian | 720x360 | `1fada775114bc0f90a9fb1338acdfd302c281331598400c328fde897106a289e` | `3485519ed2fc4df22f83b9098e02d35890b22b334b616e553652beb78fd691af` | 225.262, 227.686, 225.356, 222.650, 227.468, 223.396, 227.314 | 225.356 | 5.036 |

Box and Mean intentionally have matching output checksums: their separate
native exports dispatch independently, but `yuv_box_blur_v1.c` and
`yuv_mean_blur_v1.c` implement the same normalized uniform kernel. The runner
selects the public Dart operation by build define; `YuvAbiV1Runner.blur` maps
the two kinds to `yuv_box_blur_v1` and `yuv_mean_blur_v1` respectively.

Package commit SHA: `89e66c3b462a11b7e542530060afa7e572f6587d`.
Native source tree SHA: `d4e9e54fd92a53ce204ecc36f0031c8db3e2085c`.
Build parameters: `android-release-aot`, one operation per APK, radius 10,
Gaussian sigma 10, two warmups, seven samples. The complete machine-readable
records and captured logcat are under `doc/perf/results/blur_raw/`.

## Reproduction

From the package root, run each command separately:

```powershell
tool/bench/run_blur_pixel3.ps1 -Operation box -PackageSourcePath D:\.projects\yuv_ffi
tool/bench/run_blur_pixel3.ps1 -Operation mean -PackageSourcePath D:\.projects\yuv_ffi
tool/bench/run_blur_pixel3.ps1 -Operation gaussian -PackageSourcePath D:\.projects\yuv_ffi
```

`-PackageSourcePath` is required so the runner can stage the fixture and build
against the exact package source. The script requires two result records; on a
timeout it preserves the raw logcat and reports the latest `YUV_BLUR_STAGE`
instead of treating missing output as a timing result.
