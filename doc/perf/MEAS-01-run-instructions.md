# MEAS-01: Run Instructions (Windows Baseline)

Prepared: 2026-09-25. Executor: T2 agent.

This document records the build status and gives the ready-to-run command for the MEAS-01 Windows
baseline matrix. The physical run is performed by the user after verifying the environment controls
below.

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

## Full Matrix Run Command

Run from `D:\.projects\yuv_ffi`. The driver interleaves v024 and abi_v1 per row, runs 3 rounds,
and covers both 1080p and 12MP (skipping `*.R256` outside 1080p).

```powershell
$B = "$env:TEMP\yuv_ffi_bench"
Set-Location D:\.projects\yuv_ffi
.\tool\bench\run_matrix.ps1 `
    -Exe         "$B\bench_build\Release\yuv_bench.exe" `
    -DllV024     "$B\v024\build\Release\yuv_ffi.dll" `
    -DllAbiV1    "$B\abi_v1\build\Release\yuv_ffi.dll" `
    -InputDir    "$B\inputs" `
    -OutCsv      "$B\results\meas01_windows.csv"
```

Optional subsets for a preview or partial run:

```powershell
# Dry run — prints what would run without launching child processes:
.\tool\bench\run_matrix.ps1 ... -DryRun

# Only 1080p, 1 round, convert and flip scenarios:
.\tool\bench\run_matrix.ps1 ... -Sizes 1920x1080 -Rounds 1 -Scenarios 'CVT.*','FLIP.*'
```

## Result Locations

After the run completes:

| File | Contents |
|---|---|
| `%TEMP%\yuv_ffi_bench\results\meas01_windows.csv` | Full matrix CSV, one row per version × scenario × round |
| `%TEMP%\yuv_ffi_bench\results\meas01_windows.csv.rounds.log` | Wall-clock start/end of each round |

The CSV has 34 columns per the PERF-01 spec. Row status is `OK`, `N/A`, `TIMEOUT`, or `ERROR:*`.
The driver exits with code 1 if any row is `ERROR:*` or `TIMEOUT`.

## Expected TIMEOUT Rows

The following rows are expected to time out (> 120 s) and will be recorded as `TIMEOUT` with `t1`
as a lower bound. This is honest measurement, not a failure:

- `BOX.*.R256` (1080p only, r = 256) — all three formats
- `MEAN.*.R256` (1080p only, r = 256) — all three formats
- Possibly large blur rows at 12MP (`BOX/MEAN/GAUSS` with large radii)

## Duration Estimate

A full 3-round matrix covering 85 (1080p) + 79 (12MP) = 164 rows × 2 versions = 328 child processes
per round, × 3 rounds = 984 child processes total. Fast rows (< 5 ms) run 50 iterations; medium rows
(5–100 ms) run 30 iterations; slow rows are bounded by the 120 s watchdog. Total wall time is
estimated at **2–6 hours** depending on how many blur rows time out.

## Rebuilding From Scratch

If the `%TEMP%` directory is cleared, rebuild with the commands from `PERF-01-bench-setup.md`,
section "How to build (Release)". The source SHAs are:

| Version | SHA |
|---|---|
| 0.2.4 | `5f52fd14540a283da91a6d80e1fc7128bba1c796` |
| ABI v1 | `35c516e216fef8d5ed4ef379d38655fc643f738d` |
