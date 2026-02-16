# WASM Build Notes

This folder contains tooling to compile `src/*.c` into WebAssembly artifacts for Web runtime loading.

Current scope of this setup:
- Build pipeline and artifact layout.
- Loader bootstrap contract (`createYuvFfiModule`).

Out of scope (next step):
- Mapping/exporting YUV processing functions and wiring Dart calls to them.

## Prerequisites

1. Emscripten SDK installed and `emcc` available in PATH.
2. Run commands from repository root.

## Build Command (Shell)

```sh
sh ./tool/wasm/build_wasm.sh
```

Optional:

```sh
sh ./tool/wasm/build_wasm.sh --profile debug
sh ./tool/wasm/build_wasm.sh --emcc /opt/emsdk/upstream/emscripten/emcc
```

Windows note:
- Run via Git Bash or WSL.
- `build_wasm.sh` auto-falls back to `emcc.bat`/`emcc.cmd` when needed.
- Legacy PowerShell script (`build_wasm.ps1`) remains in repo, but shell script is the primary cross-platform path.

## Output Artifacts

- `assets/wasm/yuv_ffi.js`
- `assets/wasm/yuv_ffi.wasm`

These paths are consumed by `lib/src/loader/impl/wasm_loader_web.dart` via package assets:

- `assets/packages/yuv_ffi/assets/wasm/yuv_ffi.js`
- `assets/packages/yuv_ffi/assets/wasm/yuv_ffi.wasm`

## Export Policy (Current Stage)

The build script currently exports only:
- `_malloc`
- `_free`

This is intentional for bootstrap phase.  
Add operation exports only when wiring concrete Dart -> WASM function calls.

## Smoke Check

From repo root:

```sh
sh ./tool/wasm/build_wasm.sh --profile release
```
