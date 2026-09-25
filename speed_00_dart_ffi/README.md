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
Pop-Location
```

`YUV_FFI_DLL` must name the exact Release DLL under test. The test runs fixed
1280x720 I420, NV12 and BGRA inputs in both directions, verifies the native
status, every output sample and its checksum, warms up the function, then
reports measured native-call timings. Input setup, destination allocation and
correctness checks are outside the timed region.
