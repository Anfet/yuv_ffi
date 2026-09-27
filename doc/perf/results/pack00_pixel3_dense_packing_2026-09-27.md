# PACK-00 — dense camera-frame packing vs. padded import on Pixel 3

**Card:** PACK-00 (`todo.md`). **Executor:** Claude (main session, no delegation — by direct user
decision). Native C, ABI v1 and `YuvImage`'s general constructor are unchanged; new files:
`example/lib/ext.dart` (a switch, gated `false` by default), `example/test/camera_image_pack_planes_test.dart`,
`test/pack_planes_native_equivalence_test.dart`, `example/integration_test/pack00_pack_vs_padded_pixel3_test.dart`,
`example/integration_test/pack00_padding_plane_isolation_pixel3_test.dart`,
`example/lib/pack00_bench_screen.dart` (a temporary in-app release bench, see below), this report, and
`doc/perf/results/pack00_pixel3_raw/`.

## Retraction: the first version of this report was wrong about the bottleneck

The first version of this report, based entirely on `flutter drive --profile` measurements (the only mode
`integration_test` supports on non-web), concluded `applyRotation` cost ~93 ms on real camera content
regardless of padding, and that this — not packing — was the frame path's bottleneck. After the user ran
this project's own in-app rotate button in a real `--release` build on the same device and got ~9-12 ms,
not ~93 ms, this report was re-measured with a purpose-built in-app release bench
(`example/lib/pack00_bench_screen.dart`, reachable from the "PACK-00" button in `example/lib/main.dart`,
temporary). **`--profile` inflates this specific native FFI call by roughly 6-8x on this device; every
profile-mode rotate/BGRA number in this project's VIEW-03 and the first PACK-00 pass should be read as
profile-mode-only, not representative of the shipped app.** The release-mode numbers below are the ones
this report's conclusions are based on; the profile-mode numbers are kept in the "What `--profile`
measured" section for completeness and as a warning for future cards on this codebase.

## What "packing" means here, and how it is switched on

`example/lib/ext.dart` gained `kYuvCameraPreviewPackPlanes` (`false` by default) and a `_packPlane` helper.
When `true`, `CameraImageExt.toYuvImage()` copies each plane's *visible* samples into a new buffer with
`rowStride == columns * pixelStride` — no row padding, no gap between rows — instead of preserving the
camera's reported `bytesPerRow`. Order of U/V/UV samples, color values, frame size and rotation are
unaffected: only the row stride of the copied buffer changes. `YuvImage`'s general constructor,
`applyPlanes`, and every native symbol are untouched; the switch lives entirely in the example's camera
import path, matching the "no contract change" mandate for this card.

## Correctness first (required before any speed comparison)

Two VM test files prove the packed and padded imports carry the same visible samples before any speed
number is trusted:

- `example/test/camera_image_pack_planes_test.dart` — builds the same `CameraImageData` once, converts
  it with `kYuvCameraPreviewPackPlanes` off and on, and asserts every visible byte of every plane matches
  between the two, for I420 with a gapped U/V stride (even and odd width/height), NV12/NV21 interleaved
  UV (even and odd), BGRA8888 (even and odd), and a source buffer that omits padding after its last row.
  A ninth test checks `toInputImage()`'s `bytesPerRow` metadata reflects the packed image's own tight
  stride, not the camera's padded one, and that its `bytes` come from the packed image's own `toBytes()`.
  This file cannot call native operations in `example/`'s own `flutter test` run (`yuv_ffi`'s dynamic
  library is not next to that test binary there — a pre-existing environment limitation, not new to this
  card), so it only proves sample equality.
- `test/pack_planes_native_equivalence_test.dart` (root package, native library and `YuvFfi.initialize()`
  available, following the `nv_chroma_order_test.dart`/`native_stride_safety_test.dart` convention) —
  builds the same padded-vs-tight `YuvPlane` pairs directly and asserts `toBgraBytes()` and
  `applyRotation()` produce byte-identical output for both, for I420, NV12 and BGRA8888, even and odd
  geometry.

Both files pass: 8/8 and 6/6. Packing is a pure layout change; it does not alter what the image shows.

```
example$ flutter test test/camera_image_pack_planes_test.dart
00:00 +8: All tests passed!

$ flutter test test/pack_planes_native_equivalence_test.dart
00:00 +6: All tests passed!
```

## Release-mode result (this report's actual finding)

Since `flutter drive` (and therefore every `integration_test` in this repo) refuses `--release` on
non-web ("Use --profile mode for testing application performance"), the only way to measure the real
shipped build is inside the app itself. `example/lib/pack00_bench_screen.dart` reruns the exact VIEW-03
delivered/dropped/accepted/presented methodology
(`debugYuvCameraPreviewMobileEvent`/`debugYuvCameraPreviewMobileClock`, the same hook and the same one
real `_YuvCameraPreviewMobile` subscription VIEW-03 and the profile-mode PACK-00 runs used) from a screen
pushed by a temporary "PACK-00" button, 3 s warm-up + 10 s measurement, run twice back to back — padded,
then packed — toggling `kYuvCameraPreviewPackPlanes` between runs. Built with
`flutter build apk --release`, installed via `adb install -r`, run by the user tapping the button on the
physical device, result copied to clipboard via the screen's own copy button and pasted back.

| Variant | Delivered | Dropped (busy) | Accepted | Presented | FPS | import median | rotate median | flip median | accepted→presented median | presented gap median |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| padded | 300 | 145 | 155 | 154 | 15.4 | 1.85 ms | 14.85 ms | 2.62 ms | 20.49 ms | 65.67 ms |
| packed | 300 | 144 | 156 | 155 | 15.5 | 1.99 ms | 13.15 ms | 2.59 ms | 22.67 ms | 65.68 ms |

Delivery rate is 30 Hz (`fps: 30` requested, matched exactly), roughly double the ~15 Hz the profile-mode
runs saw for the same `delivered` count over 10 s — another sign profile mode was slowing the whole
pipeline down, not just `applyRotation`. Raw JSON: `doc/perf/results/pack00_pixel3_raw/release_build_in_app_runs.json`
(includes a third, single-variant solo run from before the two-run screen existed, consistent with these
two).

**Padded and packed are statistically indistinguishable in release**: FPS 15.4 vs 15.5, `presented_gap`
65.67 ms vs 65.68 ms (a coincidence to the second decimal, not a rounding artifact — both variants hit the
same real bottleneck). Rotate is ~14-15 ms either way — an order of magnitude below the ~93 ms every
profile-mode run measured for the identical call. Packing does not move the frame path's bottleneck or
the displayed frame rate in release, same conclusion the (wrong-magnitude) profile-mode data reached, now
on numbers that represent what ships.

**Where the frame budget actually goes, in release — the arithmetic closes exactly.** The camera delivers
at 30 Hz, a 33.33 ms period. The full per-frame pipeline —
`import (1.85-1.99 ms) + rotate (13.15-14.85 ms) + flip (2.59-2.62 ms) + accepted→presented (20.49-22.67 ms)`
— sums to **~40.5 ms**, which is *more than one* delivery period (33.33 ms) but *less than two*
(66.66 ms). So the presenter is still mid-pipeline when the very next frame is delivered (that one is
dropped by the `isBusy` gate in `_YuvCameraPreviewMobile.onNewImageAvailable`), but is free again in time
for the frame after that. The presenter therefore accepts roughly every second delivered frame, and the
real period between two presented frames lands at ≈ 2 × 33.33 ms = **66.66 ms** — against a measured
`presented_gap` of 65.67-65.68 ms in both variants, a ~1 ms difference that arithmetic and measurement
noise fully explain. This is also why `delivered=300` (30 Hz × 10 s exactly) and `accepted≈155-156`
(~52%, i.e. roughly every second frame) in both runs.

**No single operation is "the bottleneck" here — the pipeline's *total* cost (~40.5 ms) just exceeds the
33.33 ms/30 fps budget by ~7 ms, which is enough to lose the race against every second frame.** Rotate
(13-15 ms) and accepted→presented/decode+draw+vsync-wait (20-23 ms) are the two largest contributors and
together account for essentially all of the overrun; neither alone exceeds the 33.33 ms budget, but their
sum does. **The `isBusy` gate and the pipeline's total cost relative to the 30 Hz delivery period — not
packing, and not any one operation like `applyRotation` or `toBgraBytes` in isolation — set the
~15.4-15.5 displayed FPS on this device in release.** This is consistent with VIEW-03's original
(pre-third-pass) framing of the busy gate as the limiting factor, and inconsistent with the third pass's
"rotate alone is the bottleneck" conclusion, which this report now retracts as a `--profile` artifact.

## What `--profile` measured, and why it should not be trusted for this call

Two device experiments were run entirely under `flutter drive --profile` (Flutter Driver refuses
`--release` on non-web) before the release-mode bench above existed:

1. **`pack00_pack_vs_padded_pixel3_test.dart`** — the VIEW-03 methodology, four alternated runs
   (padded, packed, packed, padded), profile mode.
2. **`pack00_padding_plane_isolation_pixel3_test.dart`** — one real captured frame, four synthetic
   padding variants (all-tight, Y-only, chroma-only, both), profile mode, offline (no camera pipeline
   running while timing).

| Variant | Run | Import Y/U/V `bytesPerRow` | `rotation_us` median | Presented FPS |
| --- | --- | --- | ---: | ---: |
| padded | 0 | 768/768/768 | 93.25 ms | 6.33 |
| packed | 1 | 720/720/720 | 93.99 ms | 6.37 |
| packed | 2 | 720/720/720 | 93.69 ms | 6.36 |
| padded | 3 | 768/768/768 | 93.72 ms | 6.37 |

| Isolation variant | `rotate` median | `toBgraBytes` median |
| --- | ---: | ---: |
| all planes tight | 94.95 ms | 13.18 ms |
| Y padded only | 92.22 ms | 13.15 ms |
| chroma padded only | 95.66 ms | 13.03 ms |
| both padded | 92.76 ms | 13.50 ms |

Both experiments agreed with each other (padding does not move `rotation_us`) and with the release-mode
result (padding does not move FPS) on the *shape* of the answer, but their absolute rotate cost — ~93-95
ms — is roughly 6-8x the ~13-15 ms release-mode measured for the same call on the same device and
content. `--profile` also roughly halved the delivered rate the app actually achieves (≈15 Hz observed
under profile for a `delivered` count over 10 s that release reached at 30 Hz), so the whole pipeline, not
only the rotate call, runs slower under profiling instrumentation — consistent with `--profile` attaching
extra bookkeeping around every native FFI call.

A **synthetic, deterministic-content** padding test from VIEW-03 (`rotate_padding_isolated_pixel3_test.dart`,
unrelated to camera frames) was also re-run under `--profile` in this session and reproduced its original
7x tight/padded gap exactly (10.27 ms tight vs 69.41 ms padded,
`doc/perf/results/pack00_pixel3_raw/synthetic_padding_recheck_reference.json`) — so `--profile` is not
uniformly unreliable for every rotate call at every magnitude; it specifically inflates the real camera
frame's rotate call far more than the synthetic-content one, for reasons this card did not investigate
further (possibly related to how the native kernel accesses the two buffers differently, possibly a
profiling-instrumentation interaction with certain memory patterns). Either way, **absolute timings from
`flutter drive --profile` on this codebase's native FFI calls are not a reliable stand-in for release
behavior and must not be reported as the shipped cost without a release-mode cross-check**, a limitation
this project's earlier Pixel 3 cards (BGRA-00…05, VIEW-03) did not have the opportunity to catch because
none of them had an in-app release bench to compare against.

## Answering PACK-00's brief

- **Import cost:** packing costs ~0.1-0.7 ms more than the existing padded copy per frame at this
  resolution, in both profile and release measurements — small and consistent in direction, never a win.
- **Rotate cost:** flat across variants in release (14.85 ms padded vs 13.15 ms packed — within run-to-run
  noise) and flat across variants in profile (93.2-96.0 ms, also within noise, just at the wrong absolute
  magnitude). Packing does not reduce it in either mode.
- **BGRA cost:** not separated from `accepted_to_presented` in the release bench (the VIEW-03 hook does
  not expose a BGRA-only timestamp inside the live subscription); the profile-mode isolation test found it
  flat at ~13.0-13.5 ms regardless of padding, and the release-mode `accepted→presented` (20.5-22.7 ms,
  which includes BGRA decode + draw + vsync wait) is in the same ballpark once rotate/flip's ~16-18 ms is
  subtracted, so nothing here contradicts "BGRA cost is flat across variants" either.
- **Full path / FPS / drops:** presented FPS in release is flat at 15.4-15.5 regardless of variant;
  `dropped_busy` is ~48% of delivered frames in both variants. The mechanism is now fully accounted for:
  pipeline cost (~40.5 ms) exceeds the 33.33 ms/30 fps delivery period but not double it, so every second
  delivered frame is dropped by `isBusy` and the presenter settles at ≈ 2 × 33.33 ms = 66.66 ms between
  presented frames (measured: 65.67-65.68 ms) — unaffected by packing either way.

**Recommendation for PACK-01:** on this device and resolution, dense packing at camera-import time is not
a performance win in either profile or release measurements — it adds a small, measurable import cost and
does not move rotate, accepted→presented, or displayed FPS. The frame path's real limiter in the shipped
release build is the pipeline's *total* per-frame cost (~40.5 ms: rotate + flip + accepted→presented,
import being negligible) exceeding the 33.33 ms/30 fps delivery period by ~7 ms — just enough to lose the
`isBusy` race against every second delivered frame and settle at ~15.4-15.5 fps. No single operation is
individually over budget; packing does not change any of them enough to close a 7 ms gap (rotate's
~1.7 ms packed-vs-padded difference is an order of magnitude too small). PACK-01 should not treat "make
every `YuvImage` layout dense" as a performance justification on the strength of this data; if it is
pursued, the justification would need to be a different one (API simplicity, ML Kit/serialization
uniformity), not a speed argument. A future card wanting to raise displayed FPS to nearer 30 would need to
shave roughly 7+ ms off the combined rotate + accepted→presented cost (or reduce delivery frequency
expectations), not touch import/packing.

## Verification

- `dart format --line-length 150` on every changed/new file (both projects).
- `flutter analyze lib test --no-pub` in `example/` and `flutter analyze lib test --no-pub` in the root —
  no issues.
- `flutter test` in `example/` — 63 passed (55 existing + 8 new PACK-00 correctness tests), no existing
  test's outcome changed.
- `flutter test` in the root — 669 passed (663 existing + 6 new PACK-00 native-equivalence tests).
- Device, profile mode: both `flutter drive --profile` runs (main padded/packed comparison, four
  alternated runs; plane isolation, four synthetic variants against one captured real frame) completed
  `All tests passed`, screen kept on throughout, confirmed via `adb shell dumpsys power` before each run.
- Device, release mode: `flutter build apk --release` (`example/`), installed via `adb install -r` on
  `8B1X11QLW`, launched via `adb shell monkey`, the in-app "PACK-00" button run by the user with the
  screen on; result copied via the bench screen's clipboard button and pasted back for this report. No
  `flutter drive`/`integration_test` involved in this path — Flutter Driver refuses `--release` on
  non-web, confirmed again in this session (`flutter drive ... --release` exits with "Flutter Driver
  (non-web) does not support running in release mode").
- The synthetic-content padding test (`rotate_padding_isolated_pixel3_test.dart`) was re-run unchanged
  under `--profile` on the same device session and reproduced its original 7x effect, confirming the
  profile/release discrepancy is specific to the real camera frame's rotate call, not a general device or
  session anomaly.

## Open points

1. Why `--profile` inflates this specific call (real camera frame → `applyRotation`) by ~6-8x while
   leaving the synthetic-content rotate call's *relative* tight-vs-padded ratio intact, is unresolved —
   worth a note for whoever next relies on `--profile` absolute timings for a native FFI call in this
   project; future perf cards on Pixel 3 should cross-check against a release build before reporting
   absolute costs, the way this card had to retroactively.
2. ~~The ~25 ms gap between pipeline cost and `presented_gap` is unexplained~~ — resolved above: pipeline
   cost (~40.5 ms) exceeds one 33.33 ms delivery period but not two, so the presenter accepts every
   second delivered frame and `presented_gap` lands at ≈ 2 × 33.33 ms = 66.66 ms, matching the measured
   65.67-65.68 ms to within ~1 ms.
3. `ChangeNotifier`/`ListenableBuilder`/`notifyListeners()` in `YuvFramePresenter` were checked against
   their own source (`lib/src/widgets/yuv_frame_presenter.dart`) during this investigation: `notifyListeners()`
   is synchronous with no internal batching, and the only asynchronous boundary is a single
   `SchedulerBinding.addPostFrameCallback` waiting for the next real vsync before marking the presenter
   free — a standard, non-anomalous Flutter pattern, not a hidden source of the ~25 ms gap in point 2.
4. This device's `yuv420` camera format reports chroma `bytesPerPixel=2` (interleaved-looking) even though
   `source.format == YuvPixelFormat.i420` and U/V arrive as separate planes; not investigated further here,
   noted for whoever next touches the Android import path.
5. Measured on one device (Pixel 3, Android 12), one resolution (`ResolutionPreset.medium`, 720×480) and
   the Android front camera only — not iOS, not other resolutions, not desktop/web.
6. `kYuvCameraPreviewPackPlanes` is left in `example/lib/ext.dart`, defaulting to `false` (no behavior
   change to the shipped example); PACK-01 or a follow-up decides whether to keep, remove, or promote it.
7. `example/lib/pack00_bench_screen.dart` and the "PACK-00" button in `example/lib/main.dart` are
   temporary measurement scaffolding, not part of the example's intended feature set; a follow-up should
   decide whether to remove them or keep them as a standing in-app release-mode bench for future cards.
