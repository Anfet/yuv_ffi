# Reference blur frame: initial Pixel 3 timings

Source: `tool/bench/fixtures/blur_reference_1477x1065.png` (1477 × 1065, RGB PNG, SHA-256 `7C36DE007E221A60403FB2A17F5BBC40C8F410A8F1E74FE67FF851503825C600`). The source was converted to tight I420 before timing.

Device: Google Pixel 3 (`8B1X11QLW`). Temporary Flutter app, Android Release/AOT, package `yuv_ffi` from the local 0.4.2 checkout. The runner called the public `YuvImage.apply*Blur` method once per operation. Radius was 10; Gaussian sigma was 10. PNG decoding, RGBA→I420 conversion and the per-call source copy were outside `Stopwatch`.

| Operation | One call (ms) |
| --- | ---: |
| Box | 55.450 |
| Mean | 53.850 |
| Gaussian | 1455.532 |

These are single cold samples, not accepted baselines. There was no output checksum or direct-YUV candidate in this run. The user's earlier 15/16/320 ms readings likely used a smaller camera frame (approximately 720 × 360) and are not comparable with this 1477 × 1065, radius-10 run. The next task fixes both frame sizes, output checksums, warm-up and repeated samples.
