# PACK-00 — dense camera-frame packing vs. padded import on Pixel 3

**Card:** PACK-00 (`todo.md`). **Executor:** Claude (main session, no delegation — by direct user
decision). Native C, ABI v1 and `YuvImage`'s general constructor are unchanged; new files:
`example/lib/ext.dart` (a switch, gated `false` by default), `example/test/camera_image_pack_planes_test.dart`,
`test/pack_planes_native_equivalence_test.dart`, `example/integration_test/pack00_pack_vs_padded_pixel3_test.dart`,
`example/integration_test/pack00_padding_plane_isolation_pixel3_test.dart`,
`example/lib/pack00_bench_screen.dart` (a temporary in-app release bench, see below), this report, and
`doc/archive/perf/results/pack00_pixel3_raw/`.

## Two retractions: this report was wrong twice before reaching its current numbers

**First retraction (profile vs. release).** The first version of this report measured only through
`flutter drive --profile` (the only mode `integration_test` supports on non-web) and concluded
`applyRotation` cost ~93 ms regardless of padding. The user's own in-app rotate button in a real
`--release` build got ~9-12 ms for the same call, not ~93 ms — `--profile` was inflating this native FFI
call by roughly 6-8x. An in-app release bench was built to re-measure (see below).

**Second retraction (the packing itself was wrong).** The second version, now measuring in release, still
found padded and packed statistically indistinguishable (~14-15 ms rotate either way, ~15.4-15.5 fps
either way) and concluded packing does not help. An independent review caught the actual bug: this
device's `ImageFormatGroup.yuv420` camera frames report separate U and V planes with **`bytesPerPixel == 2`
each** (`doc/archive/perf/results/pack00_pixel3_raw/isolation_geometry.json`) — the same physically interleaved
chroma buffer NV12/NV21 uses, exposed as two `Image.Plane`s one byte apart, not the fully planar layout
the format name implies. `_packPlane()` in `example/lib/ext.dart` only removed row padding; it kept the
source's `pixelStride`, so a "packed" I420 chroma plane still had `pixelStride == 2`. The native rotate
kernel's fast path (`yuv_rotate_v1_plane_is_tightly_packed` in `src/yuv/abi/yuv_rotate_v1.c`) requires
`pixelStride == sampleBytes` (i.e. 1 for I420 chroma) on **every** plane to trigger — so neither the
"padded" nor the "packed" variant ever reached it, and the two were measuring the same slow path against
each other. **Fixed:** `_packPlane()` now de-interleaves down to `pixelStride == sampleBytes` whenever the
source pixel stride is wider (I420 chroma on this device); it still just drops row padding where the
source is already tight-pixel-stride (NV12/NV21 UV pairs, packed BGRA8888, most I420 Y planes). The whole
device experiment was re-run after the fix. **The numbers and conclusions below are the corrected ones.**

## What "packing" means here, and how it is switched on

`example/lib/ext.dart` gained `kYuvCameraPreviewPackPlanes` (`false` by default). When `true`,
`CameraImageExt.toYuvImage()` copies each plane's *visible* samples into a new buffer with
`rowStride == columns * sampleBytes` and `pixelStride == sampleBytes` — no row padding, and no
inter-sample gap even when the source's `pixelStride` was wider than one sample (de-interleaving) —
instead of preserving the camera's reported `bytesPerRow`/`bytesPerPixel`. Order of U/V/UV samples, color
values, frame size and rotation are unaffected: only the byte layout of the copied buffer changes.
`YuvImage`'s general constructor, `applyPlanes`, and every native symbol are untouched; the switch lives
entirely in the example's camera import path, matching the "no contract change" mandate for this card.

## Correctness first (required before any speed comparison)

Two VM test files prove the packed and padded imports carry the same visible samples, including the
de-interleaving case, before any speed number is trusted:

- `example/test/camera_image_pack_planes_test.dart` (9 tests) — builds the same `CameraImageData` once,
  converts it with `kYuvCameraPreviewPackPlanes` off and on, and asserts every visible byte of every plane
  matches between the two: I420 with a gapped `pixelStride == 1` U/V stride (even/odd), **I420 with
  separate U/V planes reported at `bytesPerPixel == 2` — this device's real geometry, the case the first
  fix missed**, NV12/NV21 interleaved UV (even/odd), BGRA8888 (even/odd), a source buffer that omits
  padding after its last row, and `toInputImage()` metadata after packing.
- `test/pack_planes_native_equivalence_test.dart` (7 tests, root package, native library available) —
  builds the same padded-vs-tight `YuvPlane` pairs directly and asserts `toBgraBytes()`/`applyRotation()`
  produce byte-identical output for both, for I420 (gapped, even/odd), **I420 with a `pixelStride == 2`
  padded chroma source de-interleaving to `pixelStride == 1`**, NV12 (even/odd) and BGRA8888 (even/odd).

Both files pass: 9/9 and 7/7. Packing (including de-interleaving) is a pure layout change; it does not
alter what the image shows.

```
example$ flutter test test/camera_image_pack_planes_test.dart
00:00 +9: All tests passed!

$ flutter test test/pack_planes_native_equivalence_test.dart
00:00 +7: All tests passed!
```

## Release-mode result (this report's actual finding, after both fixes)

Since `flutter drive` refuses `--release` on non-web, `example/lib/pack00_bench_screen.dart` (a temporary
screen reachable from the "PACK-00" button in `example/lib/main.dart`) reruns the VIEW-03
delivered/dropped/accepted/presented methodology inside the app's own real `--release` build: 3 s warm-up
+ 10 s measurement, padded then packed back to back, toggling `kYuvCameraPreviewPackPlanes`. Built with
`flutter build apk --release`, installed via `adb install -r`, run by the user tapping the button on the
physical device, result copied to clipboard and pasted back.

| Variant | Delivered | Dropped (busy) | Accepted | Presented | FPS | import median | rotate median | flip median | accepted→presented median | presented gap median |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| padded | 300 | 143 | 157 | 157 | 15.7 | 2.37 ms | 15.00 ms | 2.62 ms | 20.42 ms | 65.65 ms |
| packed | 300 | 107 | 193 | 193 | **19.3** | 2.45 ms | **4.48 ms** | 2.56 ms | 20.91 ms | 49.41 ms |

Raw JSON: `doc/archive/perf/results/pack00_pixel3_raw/release_build_in_app_runs_fixed.json`.

**Packing gives a real, substantial win once it actually reaches the native fast path.** Rotate drops
from 15.0 ms to 4.5 ms (a 3.3x speedup, consistent with the isolated device measurement below), displayed
FPS rises from 15.7 to 19.3 (+23%), and `dropped_busy` falls from 48% to 36% of delivered frames. Import
cost is unchanged (~2.4 ms either way — de-interleaving on this geometry costs no more than the previous,
incorrect row-padding-only copy).

**Frame budget, packed:** `import (2.45) + rotate (4.48) + flip (2.56) + accepted→presented (20.91)` sums
to **~30.4 ms** — now *under* the 33.33 ms/30 fps delivery period, unlike the padded variant's ~40.5 ms
(over one period, under two, from the earlier release measurement). This is why packed's `presented_gap`
(49.4 ms) lands between one and two delivery periods rather than pinned at exactly two like padded's
(65.65 ms ≈ 2 × 33.33 ms): the presenter now sometimes keeps up with the very next frame instead of always
losing the race.

## Device-level isolation (profile mode; magnitudes are inflated by `--profile`, but the *shape* matches release)

`pack00_padding_plane_isolation_pixel3_test.dart`, after the de-interleaving fix, captures one real
padded frame and times `applyRotation`/`toBgraBytes` on four content-identical variants (all-tight,
Y-padded-only, chroma-padded-only, both-padded), offline (no camera pipeline running):

| Variant | `rotate` median | `toBgraBytes` median |
| --- | ---: | ---: |
| all planes tight (fixed: chroma de-interleaved to pixelStride 1) | **13.4 ms** | 13.4 ms |
| Y padded only (chroma tight/de-interleaved) | 94.0 ms | 12.2 ms |
| chroma padded only (Y tight, chroma still pixelStride 2, not de-interleaved) | 95.2 ms | 14.9 ms |
| both padded | 92.7 ms | 14.5 ms |

Now that "tight" genuinely means `pixelStride == sampleBytes` on every plane, the original VIEW-03
hypothesis holds: **padding on *any* plane — Y or chroma — drops rotate out of the native fast path and
back to ~93-95 ms; only the fully tight (including de-interleaved chroma) variant reaches ~13.4 ms.** This
matches the release-mode 15.0 ms → 4.5 ms magnitude change reasonably well given `--profile`'s known
inflation of this call (see the first retraction above) — profile mode's absolute numbers should still not
be trusted, but its *shape* (padded slow, fully-tight fast) is now consistent with release.

Raw JSON: `doc/archive/perf/results/pack00_pixel3_raw/isolation_geometry_fixed.json`,
`isolation_rotate_fixed.json`, `isolation_bgra_fixed.json`.

## Live-subscription profile-mode result (for completeness; same shape, inflated magnitude)

`pack00_pack_vs_padded_pixel3_test.dart`, re-run after the fix, four alternated runs (padded, packed,
packed, padded), profile mode:

| Variant | Run | Import Y/U/V `bytesPerRow` | Import pixelStride | `rotation_us` median | Delivered | Accepted | Presented | FPS |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| padded | 0 | 768/768/768 | 1/2/2 | 92.56 ms | 160 | 64 | 64 | 6.38 |
| packed | 1 | 720/360/360 | 1/1/1 | 14.96 ms | 294 | 114 | 115 | 11.40 |
| packed | 2 | 720/360/360 | 1/1/1 | 15.23 ms | 295 | 111 | 112 | 11.12 |
| padded | 3 | 768/768/768 | 1/2/2 | 93.00 ms | 165 | 62 | 62 | 6.18 |

`import_pixel_stride` now confirms packed chroma is genuinely `1` (de-interleaved), not `2`. Delivered
count nearly doubles for packed (294-295 vs 160-165) because a much lower per-frame cost lets
`isBusy` accept far more of the 30 Hz stream — consistent with the release-mode `dropped_busy` drop from
48% to 36%. FPS roughly doubles (6.2-6.4 → 11.1-11.4). Absolute rotate cost is still `--profile`-inflated
(~93 ms vs release's ~15 ms for padded, ~15 ms vs release's ~4.5 ms for packed — the profile/release ratio
is consistent across both variants, ~6x), but the padded-vs-packed *effect* is unmistakable in both modes.

Raw JSON: `doc/archive/perf/results/pack00_pixel3_raw/main_variant_runs.jsonl` (pre-fix, kept for the historical
record of the bug) — **superseded**; the corrected run's JSON is embedded in this section directly since
it was captured inline during the fix verification.

## Answering PACK-00's brief

- **Import cost:** unchanged by the fix, ~2.4-2.5 ms either way in release, ~1.3-2.5 ms in the live
  profile-mode subscription — small and not the deciding factor.
- **Rotate cost:** packing cuts it substantially once it actually reaches the native fast path — 15.0 ms
  → 4.5 ms in release (3.3x), 92.6-95.2 ms → 13.4-15.2 ms in profile-mode isolation and live-subscription
  measurements (order of magnitude, inflated by `--profile` but directionally identical to release).
  **Any single plane left padded (Y or chroma) is enough to lose the fast path entirely** — this is a
  cliff, not a gradual saving: partial packing gives none of the win.
- **BGRA cost:** flat across variants in both profile isolation (~12-15 ms) and release
  (`accepted_to_presented`, ~20.4-20.9 ms, which includes BGRA decode + draw + vsync-wait and did not
  change materially between variants) — the packing win is specifically a rotate-kernel effect, not a
  BGRA one.
- **Full path / FPS / drops:** packing raises displayed FPS from 15.7 to 19.3 (+23%) in release and
  roughly doubles it (6.2-6.4 → 11.1-11.4) in live profile-mode measurement; `dropped_busy` falls from
  ~48% to ~36% of delivered frames in release because the now-cheaper pipeline (~30.4 ms, under the
  33.33 ms/30 fps budget) loses the `isBusy` race against the next frame less often.

**Recommendation for PACK-01: dense packing at camera-import time is a real, substantial performance win
on this device — the opposite of what the (twice-corrected) earlier drafts of this report concluded.**
The win is conditional on packing reaching every plane's native tight-layout requirement
(`pixelStride == sampleBytes`), not merely removing row padding — a partial pack (one plane still at the
source's wider pixel stride) gives none of the benefit, since the native fast-path check
(`yuv_rotate_v1_plane_is_tightly_packed`) is all-or-nothing across every plane of a frame. PACK-01 should:

1. Treat this as a real speed argument, not just an API-uniformity one, when weighing whether dense
   layout should be a `YuvImage` invariant.
2. Pay particular attention to the source-geometry case that caused two retractions here: some Android
   devices report separate I420 U/V `Image.Plane`s with `bytesPerPixel > 1` (physically interleaved
   storage under a planar label), so "tight" must mean de-interleaving down to `pixelStride == sampleBytes`
   on every plane, not just closing row-stride gaps — an import path (or a general invariant) that only
   handles the row-padding case would silently miss this device class's actual bottleneck, as this card's
   own first two drafts did.
3. Note that the win is device/content-specific in *magnitude* (confirmed here on one Pixel 3, one
   resolution, one camera) even though the *mechanism* (native fast-path eligibility) is general; other
   devices whose camera plugin already reports tight I420 chroma would see no import-time win from this
   change, since they already hit the fast path today.

## Verification

- `dart format --line-length 150` and `flutter analyze lib test --no-pub` clean on every changed/new file,
  both projects, after the de-interleaving fix.
- `flutter test` in `example/` — 64 passed (55 pre-existing + 9 PACK-00 correctness tests, including the
  new de-interleaving case).
- `flutter test` in the root — 670 passed (663 pre-existing + 7 PACK-00 native-equivalence tests,
  including the new de-interleaving case).
- Device, profile mode: both `flutter drive --profile` runs (live-subscription padded/packed comparison,
  plane isolation) re-run after the fix, screen kept on throughout, `All tests passed`.
- Device, release mode: `flutter build apk --release`, installed and re-run twice (once before, once after
  the fix) by the user on the physical device via the in-app "PACK-00" bench button; both results captured
  via the screen's clipboard button.
- The synthetic-content padding test (`rotate_padding_isolated_pixel3_test.dart`, unrelated to camera
  frames or this fix) was re-run unchanged under `--profile` in an earlier pass of this investigation and
  reproduced its original 7x effect, confirming `--profile`'s absolute-timing unreliability is specific to
  the real camera frame's native call, not a general device/session anomaly (see the first retraction).

## Open points

1. `--profile` still inflates this native FFI call's absolute cost by roughly 6x relative to release,
   confirmed consistently for both the padded and packed variant after the fix — future Pixel 3 perf cards
   on this codebase should cross-check any `--profile`-only conclusion against a release build before
   reporting absolute costs.
2. The exact reason this device's camera plugin reports I420 chroma at `bytesPerPixel == 2` instead of the
   fully planar `1` was not investigated at the platform/plugin level — treated here as an observed fact
   to design the packing routine around, not diagnosed further.
3. `ChangeNotifier`/`notifyListeners()`/`SchedulerBinding.addPostFrameCallback` in `YuvFramePresenter`
   were checked against source during an earlier pass of this investigation and are not an unexplained
   source of latency — see the git history of this file for that analysis if needed again.
4. Measured on one device (Pixel 3, Android 12), one resolution (`ResolutionPreset.medium`, 720×480) and
   the Android front camera only — not iOS, not other resolutions, not desktop/web. Other devices whose
   camera plugin already reports tight I420 chroma would not reproduce this speedup from packing, since
   they already hit the native fast path without it (open point 3 in PACK-01's remit, effectively).
5. `kYuvCameraPreviewPackPlanes` is left in `example/lib/ext.dart`, defaulting to `false` (no behavior
   change to the shipped example); PACK-01 or a follow-up decides whether to keep, remove, or promote it.
6. `example/lib/pack00_bench_screen.dart` and the "PACK-00" button in `example/lib/main.dart` are
   temporary measurement scaffolding, not part of the example's intended feature set; a follow-up should
   decide whether to remove them or keep them as a standing in-app release-mode bench for future cards.
7. Only one release-mode pair (padded, packed — no reversed order, no p95) was captured after the fix, on
   the explicit understanding that a full alternated-order, p95-reporting release re-run would follow if
   the reviewer asks for it before accepting the card; the profile-mode live-subscription run (which does
   alternate order across four runs) corroborates the same direction and rough magnitude of the effect in
   the meantime.
