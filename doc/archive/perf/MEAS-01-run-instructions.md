# MEAS-01: Windows Bench Preparation

Prepared and updated: 2026-09-25.

This document records the Windows build status and commands for an addressable smoke run of the
operation chosen when work starts.
The public Dart AOT runner is now built and checked on Windows as described in `PERF-01-bench-setup.md`.
MEAS-03 is the first per-operation baseline; later operations get a new
MEAS card when selected. Each accepted baseline covers Windows, Pixel 3 and Web before its PERF change.

## Build Status

All binaries built from extracted git sources. Build directory: `%TEMP%\yuv_ffi_bench` (expands to
`C:\Users\Oleg-T\AppData\Local\Temp\yuv_ffi_bench` on the reference machine).

| Artifact | Source commit | File | Size | Exports |
|---|---|---|---:|---|
| `v024\build\Release\yuv_ffi.dll` | `5f52fd14` (tag `0.2.4`) | `yuv_ffi.dll` | 36 352 bytes | 40 legacy symbols (`bgra8888_*`, `nv21_*`, `yuv420_*`, `nvXX_to_nvYY`) |
| `abi_v1\build\Release\yuv_ffi.dll` | `35c516e2` (`release/0.4.2`) | `yuv_ffi.dll` | 27 136 bytes | 11 `yuv_*_v1` symbols |
| `bench_build\Release\yuv_bench.exe` | `tool/bench/native/` (working tree) | `yuv_bench.exe` | 40 448 bytes | — |

Build flags (both DLLs, Release x64, MSVC 14.44.35215): `/MD /O2 /Ob2 /DNDEBUG`. No LTO, no AVX.

Export counts verified with `dumpbin.exe /exports`:
- ABI v1: exactly 11 `yuv_*_v1` symbols — matches specification.
- v024: exactly 40 legacy symbols — matches specification.

`tool/bench/build_dart_windows.ps1` also built separate Flutter Windows release executables from
`5f52fd14540a283da91a6d80e1fc7128bba1c796` and
`35c516e216fef8d5ed4ef379d38655fc643f738d` in `%TEMP%\yuv_ffi_dart_bench`. The reusable
bench sources and run driver are in `tool/bench/`; no package source or native C file was edited.
Each build writes `app_v024/bench-manifest.json` or `app_abi_v1/bench-manifest.json` next to its
temporary app. The manifest records the package commit, `src` tree, benchmark source hashes,
executable path, Flutter/Dart versions and engine content hash. The run driver checks it against
the requested SHA/tree and the current benchmark sources before launching a process. The reference
builds use Flutter 3.44.9, Dart 3.12.2 and engine content hash `b9499e4c…`. Flutter's Windows
Release DLL uses MSVC `/MD /O2 /Ob2 /DNDEBUG`, without LTO or AVX, as recorded in the manifest.

## Public Dart Smoke

`run_dart_windows.ps1` interleaved both executables for `FLIP.I420.V`, `FLIP.NV12.V` and
`FLIP.BGRA.V` at 1920×1080, one round. All six rows were `OK`; the two versions produced the
same output SHA-256 within each scenario. The CSV contains 34 columns and raw samples; the round
log was written. Five other scenario families (`CVT.RGBA.BGRA`, `ROT.BGRA.90`, `CROP.NV12.EVEN`,
`GRAY.I420.FULL`, `SWAP.NV12`) also produced ten `OK` rows. These are smoke checks, not accepted
performance baselines for MEAS-03.

The Dart driver also passed a post-rebuild `FLIP.I420.V` smoke for both versions. Its watchdog has
separate 120 s setup and first-call limits, then an adaptive limit for the measured series. A forced
zero-second setup limit produced two 34-column `TIMEOUT` rows with reasons and a nonzero driver exit.
Normal runs use the default limits; this forced timeout was only a watchdog check.

Review follow-up: the driver now skips `*.R256` at 12 MP and records `ERROR:setup` or
`ERROR:crash` if a child exits without a row, then continues with the next target and scenario.
`BOX.I420.R256,FLIP.I420.V` at 4000×3000 yielded two `FLIP` rows with `OK`.
`BAD.I420.V,FLIP.I420.V` at 1920×1080 yielded two `ERROR:setup` rows followed by two `FLIP`
rows with `OK`; the driver returned an error after writing all four rows and the round log.
The evidence is in `%TEMP%\yuv_ffi_dart_bench\results\meas01_review_skip.csv` and
`meas01_review_crash.csv` (local temporary artifacts).

The Dart checksum now packs only active samples. `CVT.NV12.I420` at 1080p matched the native C
checksum `71c06f93…` for both versions; see local
`%TEMP%\yuv_ffi_dart_bench\results\meas01_review_active_samples.csv`.
For `SWAP.NV12`, 0.2.4 public `swapNv()` returns a zeroed Y plane; the native C runner leaves
destination Y at its `0xCD` pre-fill because the legacy kernel writes UV only. Their checksums
describe these distinct outputs, so they must not be compared as equivalent results.
For ABI v1 `CVT.*.BGRA`, the public benchmark calls `toBgraBytes()` for I420/NV12 and
`toBgra()` for BGRA input. Keep those same calls in later before/after comparisons.
The Flutter process is pinned to one logical CPU, so engine and GC threads share it with the
timed call; this can contribute to spread in both versions.

The first BGRA smoke revealed that the 0.2.4 public BGRA constructor with `planes` can throw a
`RangeError` while preparing a tight 1080p input. The bench now creates a blank BGRA image and copies
the same verified input bytes into it before timing. The rerun passed without changing 0.2.4.

## Smoke Test

Scenario `CVT.I420.BGRA`, size `1920x1080`, version `abi_v1`, round 0.

```
status: OK
t1 (calibration): 168.7 ms
warmup=3, n=15, median=169.6 ms, max=172.4 ms
output checksum: b08cec9880b62a1957c53397509216d6c086ce56af2d1095840bc3d846cdc59f
```

The SHA-256 input gate passed without `ERROR:setup` — generated inputs matched the reference
checksums from PERF-01-bench-setup.md. The output checksum above is the SHA-256 of the BGRA result
buffer and will be stable across all measurements of the same row.

## Scenario Count

`--list` output: **85 scenarios at 1080p** (6 `*.R256` marked as 1080p-only, flag = 1; all others
flag = 0). Matches the specification.

## Environment Controls (Before Running)

1. **Power plan**: verify it is "High performance" or "Ultimate Performance" before starting.

   ```powershell
   powercfg /getactivescheme          # verify current plan
   ```

2. **Close** other heavy applications (builds, indexer, Flutter tooling, browser with many tabs).

3. **AC power** — do not run on battery.

4. The harness pins itself to P-core logical CPU 2 (`--affinity 0x4`) at `HIGH_PRIORITY_CLASS`
   automatically. No manual pinning needed when using `run_matrix.ps1`.

## Targeted Operation Commands

Run from `D:\.projects\yuv_ffi`. The driver interleaves v024 and abi_v1 per row. MEAS-01 uses one
1080p round to confirm the native runner. At the start of each per-operation MEAS card, replace the
example filter with that card's scenarios. The accepted baseline uses the standard three rounds and
both 1080p and 12MP; the public Dart runner and other platforms need matching scenarios.

```powershell
$B = "$env:TEMP\yuv_ffi_bench"
$ScenarioPattern = 'FLIP.*.V' # Example only; choose from the current MEAS card.
Set-Location D:\.projects\yuv_ffi
.\tool\bench\run_matrix.ps1 `
    -Exe         "$B\bench_build\Release\yuv_bench.exe" `
    -DllV024     "$B\v024\build\Release\yuv_ffi.dll" `
    -DllAbiV1    "$B\abi_v1\build\Release\yuv_ffi.dll" `
    -InputDir    "$B\inputs" `
    -OutCsv      "$B\results\meas01_selected_smoke.csv" `
    -Sizes       1920x1080 `
    -Rounds      1 `
    -Scenarios   $ScenarioPattern
```

For each accepted Windows baseline, use the same command with a new output file named for that
MEAS card and operation; omit `-Sizes` and `-Rounds` so their defaults cover 1080p, 12MP and three
rounds. Rebuild the candidate from the exact parent SHA of the selected PERF card. Pin both library
SHAs and record output checksums. For a candidate newer than `35c516e`, pass its DLL with `-DllAbiV1`
and override the driver's default metadata with `-ShaAbiV1 <parent SHA>` and
`-TreeAbiV1 <parent src tree SHA>`. Do not reuse or overwrite an earlier operation's CSV.

For a preview without launching child processes:

```powershell
.\tool\bench\run_matrix.ps1 ... -DryRun
```

## Result Locations

After the run completes:

| File | Contents |
|---|---|
| `%TEMP%\yuv_ffi_bench\results\meas01_selected_smoke.csv` | Native Windows smoke for the selected scenario filter |
| `%TEMP%\yuv_ffi_bench\results\meas01_selected_smoke.csv.rounds.log` | Wall-clock start/end of the smoke round |
| A new CSV named by MEAS ID and operation | That operation's native Windows baseline when run |

The CSV has 34 columns per the PERF-01 spec. Row status is `OK`, `N/A`, `TIMEOUT`, or `ERROR:*`.
The driver exits with code 1 if any row is `ERROR:*` or `TIMEOUT`.

After measurements, remove temporary worktrees if no longer needed:

```powershell
git worktree remove "$env:TEMP\yuv_ffi_dart_bench\source_v024"
git worktree remove "$env:TEMP\yuv_ffi_dart_bench\source_abi_v1"
```

Any `ERROR:*` requires investigation before accepting a baseline. A `TIMEOUT` for a very slow operation
is a recorded lower bound, not a numerical median; report it explicitly and investigate if unexpected.
The expected row count depends on the scenarios chosen in that MEAS card.

## Rebuilding From Scratch

If the `%TEMP%` directory is cleared, rebuild with the commands from `PERF-01-bench-setup.md`,
section "How to build (Release)". The source SHAs are:

| Version | SHA |
|---|---|
| 0.2.4 | `5f52fd14540a283da91a6d80e1fc7128bba1c796` |
| ABI v1 prepared for the first run | `35c516e216fef8d5ed4ef379d38655fc643f738d`; use the selected PERF card's parent SHA for later runs |
