# PACK-00 — dense camera-frame packing vs. padded import on Pixel 3

**Card:** PACK-00 (`todo.md`). **Executor:** Claude (main session, no delegation — by direct user
decision). Native C, ABI v1 and `YuvImage`'s general constructor are unchanged; new files:
`example/lib/ext.dart` (a switch, gated `false` by default), `example/test/camera_image_pack_planes_test.dart`,
`test/pack_planes_native_equivalence_test.dart`, `example/integration_test/pack00_pack_vs_padded_pixel3_test.dart`,
`example/integration_test/pack00_padding_plane_isolation_pixel3_test.dart`, this report, and
`doc/perf/results/pack00_pixel3_raw/`.

## What "packing" means here, and how it is switched on

`example/lib/ext.dart` gained `kYuvCameraPreviewPackPlanes` (`false` by default) and a `_packPlane` helper.
When `true`, `CameraImageExt.toYuvImage()` copies each plane's *visible* samples into a new buffer with
`rowStride == columns * pixelStride` — no row padding, no gap between rows — instead of preserving the
camera's reported `bytesPerRow`. Order of U/V/UV samples, color values, frame size and rotation are
unaffected: only the row stride of the copied buffer changes. `YuvImage`'s general constructor,
`applyPlanes`, and every native symbol are untouched; the switch lives entirely in the example's camera
import path, matching the "no contract change" mandate for this card.

## Correctness first (required before any speed comparison)

Two new VM test files prove the packed and padded imports carry the same visible samples before any
speed number is trusted:

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

## Device methodology

Real front camera on `-d 8B1X11QLW` (Pixel 3, Android 12), `ResolutionPreset.medium`, screen kept on
throughout (`adb shell svc power stayon true`, restored after) per the causal 4x screen-off swing found
for `bgra_review_2026-09-27.md`. `flutter drive` refuses `--release` on non-web; `--profile` is the
practical ceiling, as for every earlier Pixel 3 card in this project.

Two device experiments:

1. **`pack00_pack_vs_padded_pixel3_test.dart`** — the VIEW-03 methodology (one real
   `_YuvCameraPreviewMobile` subscription, `debugYuvCameraPreviewMobileEvent` diagnostic hook) run four
   times in one `testWidgets` body with `kYuvCameraPreviewPackPlanes` alternated **padded, packed,
   packed, padded** (order alternation cancels a monotonic thermal/warm-up drift from favoring either
   variant), 3 s warm-up + 10 s measurement each. Delivered/dropped/accepted/presented counts are of one
   live, working preview, not an idle listener — no second subscription competes with the measured one.
   The import geometry (`import_bytes_per_row`) that proves each run's variant actually took effect is
   captured once per run from a separate, sequential (not concurrent) one-off listen on the same platform
   stream, before the measured widget mounts.
2. **`pack00_padding_plane_isolation_pixel3_test.dart`** — captures one real padded camera frame, stops
   the stream, then builds four synthetic variants of the *same captured content* (all-tight,
   Y-padded-only, chroma-padded-only, both-padded) and times `applyRotation`/`toBgraBytes` on each
   offline (no camera pipeline running), isolating which plane's padding matters and separating import
   (packing-copy) cost from rotate/BGRA cost. This is the same isolation technique
   `rotate_padding_isolated_pixel3_test.dart` and `rotate_under_camera_load_pixel3_test.dart` used for
   VIEW-03, extended to attribute the effect to Y vs. chroma separately and to real (not synthetic)
   camera content.

Raw JSON for every run is in `doc/perf/results/pack00_pixel3_raw/`.

## Result 1 — padded vs. packed inside a real running preview

| Variant | Run | Import Y/U/V `bytesPerRow` | `to_yuv_image_us` median | `rotation_us` median | `accepted→presented` median | Delivered | Dropped (busy) | Presented | FPS |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| padded | 0 | 768/768/768 | 1.32 ms | 93.25 ms | 44.61 ms | 157 | 93 | 64 | 6.33 |
| packed | 1 | 720/720/720 | 2.06 ms | 93.99 ms | 41.96 ms | 161 | 98 | 64 | 6.37 |
| packed | 2 | 720/720/720 | 2.04 ms | 93.69 ms | 41.80 ms | 162 | 98 | 64 | 6.36 |
| padded | 3 | 768/768/768 | 1.37 ms | 93.72 ms | 44.59 ms | 155 | 91 | 64 | 6.37 |

`import_bytes_per_row` confirms the switch took effect in every run (768 = 720 + 48 bytes padding for
padded; 720 = tight for packed). `rotation_us` — the interval this project's VIEW-03 report flagged as
the bottleneck — is **statistically flat across both variants**, 93.2–94.0 ms median, well within the
run-to-run noise already seen for a single variant across VIEW-03's own repeated runs. Import
(`to_yuv_image_us`) is *slightly higher* for packed (≈2.0 ms vs ≈1.3 ms median) — the packing copy itself
costs something, as expected, and does not net out to a win. Presented FPS is flat at ≈6.3–6.4 across all
four runs regardless of variant. Packing plane data at camera-import time, alone, does not move the
frame path's bottleneck or the displayed frame rate on this device.

## Result 2 — which plane's padding, and is it the content or the layout

Offline, on one real captured 720×480 frame (`doc/perf/results/pack00_pixel3_raw/isolation_geometry.json`):
captured `Y bytesPerRow=768` (48 bytes padding over tight 720), captured chroma `bytesPerRow=768` with
`pixelStride=2` (chromaWidth 360 × 2 = 720, so also 48 bytes padding) — note this device's `yuv420`
camera format reports `bytesPerPixel=2` for U/V, an existing platform-reported detail this card observed
but did not change or investigate further.

| Variant | `rotate` median | `toBgraBytes` median |
| --- | ---: | ---: |
| all planes tight | 94.95 ms | 13.18 ms |
| Y padded only | 92.22 ms | 13.15 ms |
| chroma padded only | 95.66 ms | 13.03 ms |
| both padded | 92.76 ms | 13.50 ms |

All four are within noise of each other — **padding, on real captured content, does not measurably affect
either `applyRotation` or `toBgraBytes` on this device.** Packing the same real frame's planes
(`import_all_planes_us`) costs a median 4.89 ms by itself, separate from rotate/BGRA.

This directly contradicts VIEW-03's third-pass conclusion ("48 bytes of row padding give a 7-fold
`applyRotation` slowdown on identical content"), which was based entirely on **synthetic, deterministic
byte-pattern content** (`rotate_padding_isolated_pixel3_test.dart`). Re-running that exact synthetic test
today, on the same device, reproduces its original numbers unchanged:

```json
{"card":"rotate_padding_isolated_adhoc","device":"pixel3","tight_y_bytes_per_row":720,"padded_y_bytes_per_row":768,"tight_median_ms":10.27,"padded_median_ms":69.41}
```

So the synthetic 7x effect is real and reproducible — but it does not reproduce on real camera frame
content, where tight and padded are both ~93–95 ms regardless of stride. **The padding-cost hypothesis
from VIEW-03 was confounded by content: it holds for the synthetic deterministic byte pattern used to
isolate it, not for the camera's actual pixel data.** What makes real frame content ~9x slower to rotate
than tight synthetic content (10.3 ms) — independent of padding — is not established by this card; it
requires either a content-difference investigation (are certain byte value distributions or memory
access patterns in real footage triggering a slow path in the native kernel?) or a native-level profile,
both out of PACK-00's Dart/`example`-only mandate.

## Answering PACK-00's brief

- **Import cost:** packing costs ~0.7 ms more than the existing padded copy per frame at this resolution
  (≈2.0 ms vs ≈1.3 ms median inside the live subscription; ≈4.9 ms for a full three-plane repack measured
  in isolation, which also includes plane allocation overhead the live path's per-plane median does not
  isolate the same way).
- **Rotate cost:** flat across variants both inside the live subscription (93.2–94.0 ms) and in the
  isolated four-way plane comparison (92.2–95.7 ms) — packing does not reduce it on real content.
- **BGRA cost:** flat across variants, ~13.0–13.5 ms.
- **Full path / FPS / drops:** presented FPS is flat at 6.3–6.4 across all four live runs; `dropped_busy`
  (frames arriving while the previous one is still being processed) is present in every run at a similar
  rate (89–98 of 154–162 delivered) regardless of variant — the same `isBusy` gate VIEW-03's third pass
  identified, unaffected by packing.

**Recommendation for PACK-01:** on this device and resolution, dense packing at camera-import time is not
a performance win — it adds a small, measurable import cost and does not move `rotation_us`,
`accepted_to_presented_us`, or displayed FPS. The real 93 ms `applyRotation` cost on camera content is not
explained by row padding; whatever else differs between real camera bytes and the deterministic synthetic
pattern used earlier remains the open question, and is a native/content investigation, not a `YuvImage`
layout-contract question. PACK-01 should not treat "make every `YuvImage` layout dense" as a performance
justification on the strength of this data; if it is pursued, the justification would need to be a
different one (API simplicity, ML Kit/serialization uniformity), not the speed argument VIEW-03's third
pass raised.

## Verification

- `dart format --line-length 150` on every changed/new file (both projects).
- `flutter analyze lib test --no-pub` in `example/` and `flutter analyze lib test --no-pub` in the root —
  no issues.
- `flutter test` in `example/` — 63 passed (55 existing + 8 new PACK-00 correctness tests), no existing
  test's outcome changed.
- `flutter test` in the root — 669 passed (663 existing + 6 new PACK-00 native-equivalence tests).
- Device: both `flutter drive --profile` runs (main padded/packed comparison, four alternated runs; plane
  isolation, four synthetic variants against one captured real frame) completed `All tests passed`, screen
  kept on throughout, confirmed via `adb shell dumpsys power` before each run.
- The old synthetic-content padding test (`rotate_padding_isolated_pixel3_test.dart`) was re-run unchanged
  on the same device session to confirm its original 7x effect still reproduces on synthetic content,
  ruling out this session's device/thermal state as the reason the new real-content isolation shows no
  effect.

## Open points

1. Why real camera frame content rotates at ~93 ms regardless of row stride, while synthetic deterministic
   content at the same geometry rotates at ~10 ms tight / ~69 ms padded, is unresolved — a
   content/native-level question outside this card's Dart-only mandate.
2. This device's `yuv420` camera format reports chroma `bytesPerPixel=2` (interleaved-looking) even though
   `source.format == YuvPixelFormat.i420` and U/V arrive as separate planes; not investigated further here,
   noted for whoever next touches the Android import path.
3. Measured on one device (Pixel 3, Android 12), one resolution (`ResolutionPreset.medium`, 720×480) and
   the Android front camera only — not iOS, not other resolutions, not desktop/web.
4. `--release` is unavailable through `flutter drive` on non-web, as for every earlier Pixel 3 card in
   this project; `--profile` is the practical ceiling.
5. `kYuvCameraPreviewPackPlanes` is left in `example/lib/ext.dart`, defaulting to `false` (no behavior
   change to the shipped example); PACK-01 or a follow-up decides whether to keep, remove, or promote it.
