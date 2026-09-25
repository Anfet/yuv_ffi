# BLUR-00 Android runner

`..\\run_blur_pixel3.ps1` stages the checked fixture from the required
`-PackageSourcePath`, builds this small application as Android Release/AOT,
installs it with `adb install -r`, and saves its structured logcat output.
For Gaussian, `-Variant rgb|yonly|yuv` labels an isolated candidate build,
records the SHA-256 of its actual C source, and writes the final 1477×1065
output PNG to the app's external files directory after the timer stops.
Only one public Dart blur call is selected in each invocation. PNG decoding,
deterministic RGBA-to-public-`YuvImage.nv21` conversion and each source clone
finish before the stopwatch. In this package the legacy `nv21` constructor
stores interleaved U,V and reports `nv12`. The emitted result labels the
selected fixture bytes as `Y + UV`; it does not claim a CameraX label or raw
camera buffer establishes that byte order.

The 720 x 360 input is deterministic: crop `(0, 163, 1476, 738)` from the
1477 x 1065 PNG, then resize with `package:image` linear interpolation.
