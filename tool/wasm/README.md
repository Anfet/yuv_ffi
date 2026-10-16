# WASM Build Notes

This folder contains tooling to compile `src/*.c` into WebAssembly artifacts for Web runtime loading.

The build emits the WebAssembly module used by the Web backend. Its ABI v1
processing surface is the eleven versioned functions listed in
`lib/src/yuv/shared/yuv_abi_v1_symbols.dart`: conversion, black and white,
grayscale, negate, Gaussian/mean/box blur, crop, flip, rotate, and chroma swap.
The module also exports `_malloc` and `_free` for staging frame descriptors and
planes. `test/abi_symbol_manifest_test.dart` checks that the WASM exports agree
with the C header, ffigen allowlist, and Dart symbol list. The Web backend is
still partial; only operations documented as supported by the Web parity guide
are available there.

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

## Output Artifacts

- `assets/wasm/yuv_ffi.js`
- `assets/wasm/yuv_ffi.wasm`

These paths are consumed by `lib/src/loader/impl/wasm_loader_web.dart` via package assets:

- `assets/packages/yuv_ffi/assets/wasm/yuv_ffi.js`
- `assets/packages/yuv_ffi/assets/wasm/yuv_ffi.wasm`

## Export Policy (Current Stage)

The build script also exposes `ccall`, `cwrap`, `HEAPU8`, and `HEAP32` to the
loader. The export list and artifact paths in `build_wasm.sh` are the build
contract; this README does not define a separate export manifest.

## Smoke Check

From repo root:

```sh
sh ./tool/wasm/build_wasm.sh --profile release
```
