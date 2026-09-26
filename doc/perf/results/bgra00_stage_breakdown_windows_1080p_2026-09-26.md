# BGRA-00 — Stage breakdown of NV12/I420 → BGRA on Windows 1080p

Measured 26 September 2026 on commit `dcb336db590e25b7aa6103c2a98f6c2538e4ac2c` (release/0.4.2,
no native or `lib/` change since the `3564f5f` baseline used by
[`conversion_windows_1080p_2026-09-26.md`](conversion_windows_1080p_2026-09-26.md) other than the
already-accepted OPT-14 row-copy fast path). Native library built fresh from this SHA, Windows x64
MSVC Release, CMake `Visual Studio 17 2022`/x64; DLL SHA-256
`8F45897E07E08FDB32B87524E15BE75CEAF2EFA9CF06CDD83C3A69EC12676ABE`. Input is a fixed synthetic
1920×1080 NV12/I420 frame with deterministic byte content, tight (unpadded) strides; the same input
generator and checksum discipline as the ABI test suite.

## Purpose and method

`toBgraBytes()`/`toBgra()` for a source-to-destination conversion resolve to
`YuvAbiV1Runner.convert`, whose `_run` performs, per call: (2) allocate/copy source planes into
native buffers (`_allocateConstFrame`), (3) allocate and zero-fill the destination frame
(`_allocateMutableFrame`, `calloc`-zeroed, no ROI seed needed for a full-frame conversion), (5)
call `yuv_convert_v1` once, (7) copy destination planes back into a Dart-owned `Uint8List`
(`_copyDestinationPlanes`), then free everything in `finally`. This report times those same four
stages individually, plus the full A+B+C+D sequence, from a new standalone Dart FFI test:
[`speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart`](../../../speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart).

The runner does not call the `yuv_ffi` package; like the existing `yuv_convert_v1_test.dart`, it
drives the same ABI v1 struct layout directly against the built DLL, so the measurement stays a
read-only, package-external probe. To stay faithful to the library's actual Dart-side cost, byte
copies use the same bulk typed-list operations the library uses
(`Pointer<Uint8>.asTypedList(...).setAll(...)` for staging in, `Uint8List.fromList(...asTypedList...)`
for copy-out) rather than a per-byte Dart loop — an earlier draft of this runner used per-byte loops
and measured staging/copy-out roughly 5–45× too slow; that draft's numbers are not reported here.

Each stage/pair ran 5 warm-up iterations then 30 timed iterations; input generation and the
independent BGRA oracle/checksum (BT.601, same formula as `yuv_convert_v1_test.dart`) are outside
every timed region. Every timed run's output was checked byte-for-byte against the oracle via an
FNV-1a checksum; all runs matched.

**Important caveat on absolute numbers:** this harness runs under the Dart VM/JIT (`dart test`),
not Flutter AOT release, which is what the existing 43–44 ms full-call figure in
`conversion_windows_1080p_2026-09-26.md` was measured under. The two `full_call` numbers here
(~27–28 ms) are **not** directly comparable in absolute terms to that AOT figure — different
compiler, different runtime. What this report adds is the internal proportion between stages, and
the kernel-only number, which is directly comparable to the AOT-era kernel share because
`yuv_convert_v1` itself is native code called identically either way.

## Results (median of 30 runs, three rounds)

All three rounds are in
[bgra00_stage_breakdown_windows_1080p_raw.csv](bgra00_stage_breakdown_windows_1080p_raw.csv)
(min/median/max, n=30, checksum per row). Medians below are round 1; rounds 2–3 agree within noise
(see raw CSV).

| Pair | Stage | Median, ms | Share of full_call |
| --- | --- | ---: | ---: |
| NV12→BGRA | staging (source calloc + bulk copy-in) | 3.72 | 13.7% |
| NV12→BGRA | dest_alloc_zero (calloc destination, `calloc`-zeroed) | 9.20 | 33.9% |
| NV12→BGRA | kernel (`yuv_convert_v1` call alone) | 12.11 | 44.6% |
| NV12→BGRA | copy_out (bulk copy destination to Dart) | 1.95 | 7.2% |
| NV12→BGRA | **full_call** (A+B+C+D, matches `toBgraBytes()` shape) | **27.16** | 100% |
| I420→BGRA | staging | 4.01 | 14.4% |
| I420→BGRA | dest_alloc_zero | 9.11 | 32.7% |
| I420→BGRA | kernel | 12.76 | 45.8% |
| I420→BGRA | copy_out | 1.95 | 7.0% |
| I420→BGRA | **full_call** | **27.86** | 100% |

Sum of the four stage medians (NV12: 26.98 ms, I420: 27.83 ms) accounts for essentially all of
`full_call`'s own median (27.16 ms/27.86 ms); the small residual is struct/options allocation and
loop overhead not attributed to any one stage, plus run-to-run scheduling noise.

## Reading

- **The native kernel (`yuv_convert_v1`) is the largest single stage** at 44.6% (NV12) / 45.8%
  (I420) of the full call, consistent with `conversion_windows_1080p_2026-09-26.md`'s reading of
  `yuv_convert_to_bgra` as the primary candidate: format dispatch and per-pixel address
  computation repeat inside the pixel loop.
- **Destination allocation/zero-fill is the second-largest stage** at roughly a third of the full
  call (9.1–9.2 ms for a 1920×1080×4 = 8,294,400-byte `calloc`). This is a real cost, not
  measurement noise: it reproduces the same `calloc`-on-large-buffers cost OPT-13 already flagged,
  now isolated for the BGRA destination specifically. A full-frame BGRA conversion overwrites every
  destination byte, so the zero-fill itself is throwaway work the kernel immediately replaces —
  this is exactly BGRA-03's target ("убрать лишнее обнуление только у полностью перезаписываемых
  байтовых буферов").
  Because `dest_alloc_zero` is larger than `copy_out`, and only marginally smaller than `staging`,
  BGRA-03 is significant here and should not be deprioritized relative to BGRA-04.
- **Input staging is smaller but non-trivial** at 13.7–14.4%, driven by the bulk copy of every
  source plane into a fresh native buffer.
- **Copy-out is the smallest stage** at ~7%, once the library's own bulk `asTypedList`/
  `Uint8List.fromList` path is used instead of a per-byte loop. This makes BGRA-04's target (reduce
  native→Dart copy) the least significant of the three Dart-side candidates by this measurement,
  though OPT-13 already found this copy path costly in absolute terms on other workloads
  (44 ms → 0.8–1.1 ms tight-row experiment on a different scenario) — the two findings are not in
  conflict: BGRA-04 has more theoretical headroom per byte, but this stage is already small
  relative to the whole call at this size after OPT-14's row-copy fast path landed.

## Pixel 3 / Android

Not measured. This environment has no access to a Pixel 3 or any Android device or Mac-runner
bridge; per the task's constraints, no Android numbers are fabricated. Pixel 3 720×360 measurement
for BGRA-00 remains outstanding and should be picked up by whichever executor has Mac-runner/Android
access, using the same
`speed_00_dart_ffi/test/yuv_convert_v1_bgra_stages_test.dart` methodology (width/height constants
would need to change to 720×360 for that run, or the test parameterized — currently hard-coded to
1920×1080 per this task's Windows-only scope).

## Recommendation for task order

Ranking `yuv_convert_v1` kernel > destination alloc/zero-fill > staging > copy-out by measured
share of the full call:

1. **BGRA-01/BGRA-02 (native kernel, NV12 then I420 branch of `yuv_convert_to_bgra`)** — largest
   single share (~45%) of the full call, and the only stage where the existing report already
   identified a concrete inefficiency (format dispatch inside the pixel loop). Highest expected
   payoff per unit of effort.
2. **BGRA-03 (destination zero-fill removal)** — second-largest share (~33%), directly measured
   here as throwaway work for a full-frame conversion. Should be attempted before BGRA-04, not
   after, contrary to the todo's numeric listing order — the two are independent (different
   dependency notes: "BGRA-00: подготовка/zero-fill значимы" is now confirmed true) and can be
   sequenced by whoever picks up the active cycle next.
3. **BGRA-04 (copy-out reduction)** — smallest measured share (~7%) at this size on the tight,
   unpadded 1080p input, after OPT-14's row-copy fast path already landed. Still worth the isolated
   check the card asks for (padded/ROI cases may differ), but should not be assumed to unlock a
   comparable win to BGRA-01–03 without evidence at other layouts.
