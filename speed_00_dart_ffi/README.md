# SPEED-00 Dart FFI harness

This package invokes the current ABI v1 Windows Release DLL directly from the
Dart VM. It does not use the Flutter API or `tool/bench/`.

From the repository root, build the current checkout outside the repository
and run the targeted test:

```powershell
$cmake = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$build = Join-Path $env:TEMP 'yuv_ffi-speed-00-release'
& $cmake -S src -B $build -G 'Visual Studio 17 2022' -A x64
& $cmake --build $build --config Release
$env:YUV_FFI_DLL = Join-Path $build 'Release\yuv_ffi.dll'
Push-Location speed_00_dart_ffi
dart pub get
dart test test/yuv_flip_v1_test.dart -r expanded
dart test test/yuv_crop_v1_test.dart -r expanded
dart test test/yuv_rotate_v1_test.dart -r expanded
dart test test/yuv_grayscale_v1_test.dart -r expanded
Pop-Location
```

`YUV_FFI_DLL` must name the exact Release DLL under test. The test runs fixed
1280x720 I420, NV12 and BGRA inputs in both directions, verifies the native
status, every output sample and its checksum, warms up the function, then
reports measured native-call timings. Input setup, destination allocation and
correctness checks are outside the timed region.

The crop test covers aligned, odd-origin and odd-edge crops for I420 and
NV12, plus BGRA crops and an I420 padded-source fallback check.

The rotate test covers I420, NV12 and BGRA at 90, 180 and 270 degrees. It
checks transposed destination geometry for quarter turns, every output byte
and an FNV-1a checksum.

The grayscale test covers I420, NV12 and BGRA with full-frame and odd-boundary
ROI effects. It checks every output byte against an independent BT.601 oracle,
preserves BGRA alpha, includes an I420 padded-source fallback, and reports an
FNV-1a checksum after each timed batch.

For C-02, use the same Release DLL setup and run:

```powershell
dart test test/yuv_convert_v1_test.dart -r expanded
```

The conversion test covers all twelve ABI v1 pairs on a fixed 1281x721 image.
It checks every output byte against an independent Dart oracle and reports an
FNV-1a checksum. Five warm-up calls precede one timed batch of thirty native
calls per pair; fixture setup and correctness checks are outside the timer.
