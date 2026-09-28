# MEAS-02: Android Pixel 3 and Web runners

Prepared: 2026-09-25. This is runner preparation, not a performance baseline.
Raw CSV files stay separate from MEAS-03's reduced baseline.

## Common contract

Each platform app runs one fixed, addressable matrix in one invocation:
`FLIP.I420.V`, `FLIP.NV12.V`, `FLIP.BGRA.V` × 1920×1080, 4000×3000 × rounds
1, 2, 3. It emits exactly 18 PERF-01 34-column raw rows. Input setup, the
mandatory SHA-256 verification of every pristine input, fresh image creation,
and packed-active-output checksumming stay outside `Stopwatch`. The matrix core
uses PERF-01's xorshift32 SHA table for all three formats and both sizes.

The public call is vertical flip. Every row has `direction=V`, `layout=tight`
and `level=dart`; each platform driver rejects a duplicate, missing or metadata
mismatched row before it writes the raw CSV.

References are fixed before execution:

| Version | Package SHA | src tree |
|---|---|---|
| v024 | `5f52fd14540a283da91a6d80e1fc7128bba1c796` | `eba076b4cc9a0d7a686b61edbbb8101da9270356` |
| ABI v1 | `35c516e216fef8d5ed4ef379d38655fc643f738d` | `9029ff28d9834c069f41159d122b36ed6d9d4968` |

## Pixel 3

The connected target is serial `8B1X11QLW`. The runner creates an exact
detached worktree and a temporary Flutter app under `%TEMP%`, compiles an APK
in release mode, and launches it. It uses **only** `adb install -r`; it never
uses uninstall or `pm clear`. The app emits all 18 CSV rows through the
`yuv_bench` logcat tag. The driver waits for and validates the complete matrix
before it writes the raw file.

```powershell
.\tool\bench\run_dart_android.ps1 -Version v024 `
  -OutCsv "$env:TEMP\yuv_ffi_dart_bench\results\meas02_android_v024_raw.csv"
.\tool\bench\run_dart_android.ps1 -Version abi_v1 `
  -OutCsv "$env:TEMP\yuv_ffi_dart_bench\results\meas02_android_abi_v1_raw.csv"
```

`OK` proves the input SHA, public invocation and repeatable output checksum for
that row. `UNSUPPORTED` is retained as a valid, explicit outcome. `ERROR:*`,
an absent row or a partial matrix are failures with their logcat evidence.

## Flutter Web JS/WASM

`run_dart_web.ps1` is intentionally ABI-v1-only. It builds the package WASM
assets with `bash ./tool/wasm/build_wasm.sh --profile release`, then builds the
temporary Flutter app with `flutter build web --release`. It serves the
ordinary release JS bundle and runs it in the installed real Chrome binary in
headless mode; it does not use `flutter build web --wasm`. Chrome creates one
`pre.bench-result` DOM element per CSV row and adds `#bench-complete` only after
all 18 rows. The driver requires that completion marker and validates all 18
rows after `YuvFfi.initialize()` loads the package WASM backend; a build by
itself is not accepted as runtime evidence.

```powershell
.\tool\bench\run_dart_web.ps1 `
  -OutCsv "$env:TEMP\yuv_ffi_dart_bench\results\meas02_web_abi_v1_raw.csv"
```

Web remains a partial WASM backend. A Web `OK` establishes only the individual
matrix row and does not claim native feature parity. Legacy 0.2.4 has
no supported JS/WASM package backend compatible with this runner; record its
build/runtime failure as a separate `UNSUPPORTED` raw CSV row with the command
output, rather than substituting an ABI-v1 result.

## MEAS-03 handoff

Keep the platform raw files named above unchanged. MEAS-03 may reduce only its
selected validated rows into its final baseline and must retain raw samples,
SHA fields, status/reason and browser/device evidence.
