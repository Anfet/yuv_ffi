#!/usr/bin/env sh
#
# Cross-platform WASM build script for yuv_ffi.
# Designed to run on:
# - macOS Terminal (sh/bash/zsh)
# - Windows via Git Bash or WSL
#
# What this script does:
# 1) Collects C sources from `src/` (excluding any `build/` directories).
# 2) Compiles them with Emscripten (`emcc`) into:
#    - assets/wasm/yuv_ffi.js
#    - assets/wasm/yuv_ffi.wasm
# 3) Keeps export list intentionally minimal for bootstrap phase.
#
# Why shell script:
# - same invocation pattern across macOS and Windows shell environments.
# - no PowerShell-specific behavior.

set -eu

print_help() {
  cat <<'EOF'
Usage:
  sh ./tool/wasm/build_wasm.sh [options]

Options:
  --profile <debug|release>   Build profile (default: release)
  --out-dir <path>            Output directory (default: assets/wasm)
  --emcc <path-or-command>    emcc command/path (default: emcc)
  -h, --help                  Show help

Examples:
  sh ./tool/wasm/build_wasm.sh
  sh ./tool/wasm/build_wasm.sh --profile debug
  sh ./tool/wasm/build_wasm.sh --emcc /opt/emsdk/upstream/emscripten/emcc
EOF
}

PROFILE="release"
OUT_DIR="assets/wasm"
EMCC="emcc"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      PROFILE="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --emcc)
      EMCC="${2:-}"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      print_help >&2
      exit 2
      ;;
  esac
done

if [ "$PROFILE" != "debug" ] && [ "$PROFILE" != "release" ]; then
  echo "Invalid profile: $PROFILE (expected: debug or release)" >&2
  exit 2
fi

# Git Bash on Windows may expose Emscripten as emcc.bat/cmd.
# If default "emcc" is not discoverable, try common Windows launcher names.
if [ "$EMCC" = "emcc" ] && ! command -v "$EMCC" >/dev/null 2>&1; then
  if command -v emcc.bat >/dev/null 2>&1; then
    EMCC="emcc.bat"
  elif command -v emcc.cmd >/dev/null 2>&1; then
    EMCC="emcc.cmd"
  fi
fi

if ! command -v "$EMCC" >/dev/null 2>&1; then
  echo "emcc not found: $EMCC" >&2
  echo "Install Emscripten SDK and ensure emcc is available in PATH." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# Build the tracked source list in Git index order.  Emscripten preserves input
# order in generated artifacts, so filesystem traversal made identical builds
# differ between workstations and CI.  The pathspec excludes build/ directories
# without retrieving their contents.
SOURCE_PATHS="$(git ls-files -- 'src/*.c' 'src/**/*.c' ':!**/build/**')"
SOURCE_COUNT="$(printf '%s\n' "$SOURCE_PATHS" | sed '/^$/d' | wc -l | tr -d ' ')"
if [ "$SOURCE_COUNT" = "0" ]; then
  echo "No tracked C sources found under src/." >&2
  exit 1
fi

if [ "$PROFILE" = "release" ]; then
  OPT_LEVEL="-O3"
  # WebAssembly SIMD, so the conversion loops vectorize the same way they do on
  # native targets. Safari added 128-bit WebAssembly SIMD in Safari 16.4;
  # older Safari versions cannot instantiate a SIMD-enabled module.
  SIMD_FLAG="-msimd128"
else
  OPT_LEVEL="-O0"
  SIMD_FLAG=""
fi

# The eleven `_yuv_*_v1` entries are the versioned status-returning symbols
# from doc/api-abi-0.4-design.md section 11, and they are the module's entire
# processing surface: YUV-52 removed the legacy per-format sources
# (yuv420_*/nv21_*/bgra8888_*/nvXX_to_nvYY), so there is nothing else left to
# export. The Web backend calls these directly (lib/src/yuv/impl/web/), so a
# name dropped from this list goes missing at the Dart call site rather than
# at link time -- test/abi_symbol_manifest_test.dart cross-checks this list
# against the C header, the ffigen allowlist and the Dart symbol manifest.
# `_malloc`/`_free` stay because the Dart side stages descriptors and planes
# in WASM linear memory itself.
EXPORTED_FUNCTIONS="['_malloc','_free','_yuv_convert_v1','_yuv_black_white_v1','_yuv_grayscale_v1','_yuv_negate_v1','_yuv_gaussian_blur_v1','_yuv_mean_blur_v1','_yuv_box_blur_v1','_yuv_crop_v1','_yuv_flip_v1','_yuv_rotate_v1','_yuv_chroma_swap_v1']"
EXPORTED_RUNTIME_METHODS="['ccall','cwrap','HEAPU8','HEAP32']"

OUTPUT_JS="$OUT_DIR/yuv_ffi.js"

echo "== yuv_ffi WASM build =="
echo "Emcc:    $EMCC"
echo "Profile: $PROFILE"
echo "OutDir:  $OUT_DIR"
echo "Sources: $SOURCE_COUNT"

# xargs receives Git's NUL-separated index paths, preserving paths with spaces.
git ls-files -z -- 'src/*.c' 'src/**/*.c' ':!**/build/**' | \
  xargs -0 "$EMCC" \
    "$OPT_LEVEL" \
    $SIMD_FLAG \
    -Isrc \
    -sWASM=1 \
    -sMODULARIZE=1 \
    -sEXPORT_NAME=createYuvFfiModule \
    -sALLOW_MEMORY_GROWTH=1 \
    -sENVIRONMENT=web \
    "-sEXPORTED_FUNCTIONS=$EXPORTED_FUNCTIONS" \
    "-sEXPORTED_RUNTIME_METHODS=$EXPORTED_RUNTIME_METHODS" \
    -o "$OUTPUT_JS"

# Emscripten 3.1.74 leaves horizontal whitespace on generated JS lines. Strip
# only that whitespace so the checked-in artifact passes Git's whitespace gate;
# the WASM binary remains exactly as emitted by the compiler.
NORMALIZED_JS="$OUTPUT_JS.normalized"
sed 's/[[:blank:]]*$//' "$OUTPUT_JS" > "$NORMALIZED_JS"
mv "$NORMALIZED_JS" "$OUTPUT_JS"

echo "Build completed:"
echo " - $OUTPUT_JS"
echo " - $OUT_DIR/yuv_ffi.wasm"
