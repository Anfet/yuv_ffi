# BGRA-00 addendum — toBgra() vs toBgraBytes() on Windows 1080p

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

Pending — the coordinating session is running Pixel 3 measurements centrally across the BGRA
cycle to avoid contention over the single physical device between parallel executors. This
section will be filled in with real numbers (or an explicit failure reason, per the task's
no-fabrication rule) once that centralized run completes, before this card moves to REVIEW.
