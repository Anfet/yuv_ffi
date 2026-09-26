# BGRA-00 addendum — toBgra() vs toBgraBytes() on Windows 1080p and Pixel 3 720×360

Measured 26 September 2026 on `release/0.4.2` HEAD `3ca75a79f371f4f123dfc395c6dce9194e728c5e`.
Closes the first gap independent review found in the original BGRA-00 report
(`doc/perf/results/bgra_independent_review_2026-09-26.md`, BGRA-00 row: "Нет ... отдельного
замера `toBgra()` в том же протоколе"). This addendum does not repeat or reinterpret the
original stage numbers; it adds the one measurement that was missing and keeps the original
report's readings about kernel/dest_alloc/staging/copy_out shares unchanged.

## Why `toBgra()` needs its own stage

`toBgraBytes()` (`lib/src/yuv/impl/io/yuv_image.dart`) calls `YuvAbiV1Runner.convert(...)` and
returns `result.planes[0]` directly — staging, destination alloc/zero-fill, kernel, copy-out,
nothing else. `toBgra()` (`_toIndependent` in the same file) calls the exact same
`YuvAbiV1Runner.convert(...)` with the same tight BGRA destination layout, then additionally
wraps the copied-out bytes into a public `YuvImage`:
`YuvAbiV1ImageTransport.planesOf()` builds a `YuvPlane` per result plane (adopts the existing
`Uint8List`, no further byte copy for BGRA's single plane), and `YuvImageImpl(...)` constructs
its `YuvImageState` around that plane list. So `toBgra()`'s cost is `toBgraBytes()`'s cost plus
one extra, cheap wrap step — not a different conversion path.

## Method

Extended the existing read-only external FFI runner
([`speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart`](../../../speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart))
with two more timed regions, same 30-run/5-warmup/3-round protocol, same FNV-1a byte-exact check
against the independent oracle on every run:

- **wrap** — times only the `YuvPlane`+`YuvImageImpl` construction over the bytes `copy_out`
  already produced (i.e. what `toBgra()` does *after* `YuvAbiV1Runner.convert` returns, before
  freeing native memory).
- **toBgra_full_call** — staging + dest_alloc_zero + kernel + copy_out + wrap end to end, timed
  as one region, directly comparable to the existing **full_call** (`toBgraBytes()`'s shape).

This package has no Flutter dependency (`speed_00_dart_ffi/pubspec.yaml`), and the real
`YuvPlane` imports `package:flutter/foundation.dart`, so the wrap stage uses a local
`_PlaneProxy`/`_ImageProxy` pair that replicates `YuvPlane`'s constructor field assignment and
its `bytes.length != height * rowStride` validation branch exactly, without pulling in Flutter.
This proxy only stands in for the cheap wrap step — the conversion kernel and every byte that
crosses the FFI boundary still go through the real `yuv_convert_v1` and the same bulk
`asTypedList`/`Uint8List.fromList` calls the library itself uses, exactly as in the original
BGRA-00 report.

Native library: reused the already-built Windows x64 MSVC Release `yuv_ffi.dll` from the BGRA-02
cycle (SHA-256 `9C816B9F59EE159573575C2916321693AE035161D99B92274D9FC21A22365F30`), since
`git diff 5b233c7aea6f2ec8179c9362a3e49f34c069c15c HEAD -- src/` is 0 lines — native code has not
changed since that build, and this task does not touch `src/` per its constraints.

## Results (median of 30 runs, three rounds)

Raw samples:
[bgra00_stage_breakdown_windows_1080p_tobgra_raw.csv](bgra00_stage_breakdown_windows_1080p_tobgra_raw.csv).

| Pair | Stage | Round 1 | Round 2 | Round 3 |
| --- | --- | ---: | ---: | ---: |
| NV12→BGRA | full_call (toBgraBytes shape) | 59.9488 ms | 60.0658 ms | 59.8607 ms |
| NV12→BGRA | wrap | 0.0086 ms | 0.0104 ms | 0.0072 ms |
| NV12→BGRA | **toBgra_full_call** | **59.9239 ms** | **59.9125 ms** | **59.6511 ms** |
| I420→BGRA | full_call (toBgraBytes shape) | 66.3127 ms | 66.9024 ms | 67.3262 ms |
| I420→BGRA | wrap | 0.0083 ms | 0.0085 ms | 0.0076 ms |
| I420→BGRA | **toBgra_full_call** | **66.5781 ms** | **66.3826 ms** | **66.7988 ms** |

Checksum identical across every run and stage: NV12→BGRA `0xbd2817acd7e16391`, I420→BGRA
`0x9fb2849898309858` — same values as the original BGRA-00 report and every accepted BGRA-01/02
report, confirming the wrap step does not touch or corrupt the converted bytes.

**Note on absolute numbers.** This run's `full_call`/`kernel` medians (~44–51 ms kernel, ~60–67 ms
full_call) are higher than the original BGRA-00 report's pre-BGRA-01/02 baseline (~12 ms
kernel, ~27–28 ms full_call) even though this DLL already has BGRA-01/02's optimized NV12/I420
kernels merged — this is machine load on a shared dev box during this session, not a regression:
all three rounds here agree with each other within noise, and the *comparison this addendum
exists to make* (toBgra_full_call vs full_call) is a same-run, same-load, same-DLL ratio, so it is
unaffected by the absolute noise level. A controlled re-run for absolute kernel numbers is BGRA-05's
job, not this addendum's.

## Reading

- **wrap is negligible**: ~0.007–0.010 ms, roughly **0.01–0.02% of full_call**. It is three to four
  orders of magnitude smaller than any of the four stages the original report measured (copy_out,
  the smallest of those, is ~2 ms).
- **toBgra_full_call ≈ full_call within noise**, both directions: the largest observed difference
  across all 6 (pair × round) comparisons is 0.75 ms (I420 round 3, 66.80 vs 67.33 ms — in the
  direction of toBgra being *faster*, i.e. noise, not a real cost), and NV12's differences are all
  under 0.35 ms. `toBgra()` does not have a materially different performance profile from
  `toBgraBytes()`: the same four stages dominate both, and the extra wrap step this task was asked
  to measure separately is not a fifth candidate stage for future optimization.
- This confirms the original report's staged breakdown (kernel > dest_alloc_zero > staging >
  copy_out) and its task-order recommendation apply unchanged to `toBgra()`, not only to
  `toBgraBytes()`.

## Pixel 3 720×360

Run by the coordinating session on the real device (`8B1X11QLW`) to avoid contention over the
single physical device between parallel executors, using
[`example/integration_test/bgra00_stage_breakdown_pixel3_test.dart`](../../../example/integration_test/bgra00_stage_breakdown_pixel3_test.dart).
That file documents, in its own header comment, why this is **not** a 4-stage breakdown the way
the Windows runner is: `staging`/`dest_alloc_zero`/`kernel`/`copy_out` are internal steps of
`YuvAbiV1Runner._run`, which is unexported from `package:yuv_ffi`'s public surface
(`lib/yuv_ffi.dart`) — an on-device `integration_test` can only reach `YuvImage.toBgraBytes()`/
`toBgra()`, which run all four steps as one call with no hook to time a step in isolation. So the
Android side of this addendum has exactly one stage — **full_call** — for each of
`toBgraBytes()` and `toBgra()`, not the five Windows has.

`flutter drive`/`integration_test` run against 720×360 NV12/I420→BGRA, warm-up 5 + 30 timed
samples per pair/call, byte-exact checked every run against an independent pure-Dart BT.601
round-trip oracle (`example/integration_test/helpers/bgra_round_trip_oracle.dart`) via SHA-256,
not the Windows runner's FNV-1a — a different but equally independent oracle, appropriate for a
different harness. Result: **"All tests passed"**, checksum identical on every run,
`1638d13f0aab5308d972d00d7611f1cdb928de29bafc4c06907e0793ac3ecf55`.

| Pair | Call | median | min | max | n |
| --- | --- | ---: | ---: | ---: | ---: |
| NV12→BGRA | toBgraBytes() | 11.40 ms | 11.06 ms | 13.09 ms | 30 |
| NV12→BGRA | toBgra() | 12.35 ms | 12.15 ms | 15.23 ms | 30 |
| I420→BGRA | toBgraBytes() | 11.38 ms | 11.11 ms | 25.47 ms (single outlier; rest consistent with NV12) | 30 |
| I420→BGRA | toBgra() | 12.30 ms | 12.07 ms | 14.20 ms | 30 |

### Observation: the toBgra()-vs-toBgraBytes() gap is not negligible on this device

On Windows (above), `wrap` was ~0.007–0.010 ms — 0.01–0.02% of `full_call`, indistinguishable from
noise. On Pixel 3, `toBgra()` costs **~0.9–1.0 ms more than `toBgraBytes()`** on both pairs
(NV12: 12.35 − 11.40 = 0.95 ms; I420: 12.30 − 11.38 = 0.92 ms), which is roughly **8% of the whole
call** — far above anything the Windows measurement would predict. This report does not paper
over that mismatch with the Windows conclusion ("toBgra_full_call ≈ full_call within noise"),
because the Android numbers say otherwise for the *wrap-equivalent* delta specifically.

Two things are true at once and should not be confused:

- The **conversion path itself** (staging + dest_alloc + kernel + copy_out, i.e. what
  `toBgraBytes()` measures) cannot be isolated on Android through the public API, so this report
  cannot say whether Android's wrap step alone is ~1 ms or whether some of that gap is JIT/AOT
  warm-up variance between two back-to-back calls that allocate a fresh source `YuvImage` each
  time (`_buildSourceImage(...)..applyRgbaBytes(rgba)` runs once per sample for *both* loops in
  the Pixel 3 test, so both loops pay an extra RGBA→YUV `applyRgbaBytes` conversion that the
  Windows FFI runner's staged stages never had to do at all — the two harnesses are not measuring
  identical work upstream of the BGRA conversion, which the next paragraph explains).
- The Windows `wrap` proxy measured *only* `YuvPlane`+`YuvImageImpl` construction over
  already-copied bytes — a few object allocations, no I/O. If Android's `YuvImageImpl`
  construction path (`YuvImageState`'s constructor, invoked by both `toBgra()`'s wrap and,
  identically, every other `YuvImageImpl` factory) is meaningfully more expensive on the Dart
  AOT/ARM runtime than proxy-measured on Windows Dart-VM/JIT, or if `YuvImageState`'s constructor
  does non-trivial validation this addendum's Windows proxy did not replicate byte-for-byte (the
  proxy only replicates `YuvPlane`'s own constructor, not `YuvImageState`'s, which is a different,
  unproxied class further inside `YuvImageImpl`), that would show up as exactly this kind of
  platform-specific gap without being a measurement error on either side.

**This is flagged as an open, unresolved discrepancy, not resolved here.** The Windows
conclusion ("toBgra() does not have a materially different performance profile from
toBgraBytes()") holds for Windows Dart-VM/JIT as measured; it does not extend to Android
Flutter AOT/ARM, where the wrap-equivalent gap is measured, real, and an order of magnitude
larger in relative terms (~8% vs ~0.02%). Whoever next touches `toBgra()`'s wrap step (most
likely inside a future BGRA-05 rollup, since neither BGRA-00 nor any BGRA-01…04 card scopes a
wrap-step optimization) should treat this Android number as the one that matters for a
mobile-first target, not the Windows one, and should isolate `YuvImageState` construction cost on
Android specifically before concluding wrap is safe to ignore there the way it is on Windows.

Structural constraint (from the Pixel 3 test file's own header comment, not this addendum): a
true staged Android breakdown would require either exporting `YuvAbiV1Runner` from the public
package surface, or building an Android cross-compiled `dart:ffi` runner that opens the on-device
`.so` directly the way the Windows runner opens `yuv_ffi.dll` — both are out of scope for a
measurement-only task and are noted as open follow-up work, not attempted here.
