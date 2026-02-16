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

# Build source list excluding build directories.
# AGENTS policy requires build/ to be ignored for content retrieval/processing.
SOURCE_COUNT="$(find src -type f -name '*.c' ! -path '*/build/*' | wc -l | tr -d ' ')"
if [ "$SOURCE_COUNT" = "0" ]; then
  echo "No C sources found under src/." >&2
  exit 1
fi

if [ "$PROFILE" = "release" ]; then
  OPT_LEVEL="-O3"
else
  OPT_LEVEL="-O0"
fi

# IMPORTANT:
# We intentionally export only runtime memory helpers at this stage.
# Processing exports will be added when Dart -> WASM operation wiring starts.
EXPORTED_FUNCTIONS="['_malloc','_free','_yuv420_blackwhite','_nv21_blackwhite','_bgra8888_blackwhite','_yuv420_flip_horizontally','_nv21_flip_horizontally','_bgra8888_flip_horizontally','_yuv420_flip_vertically','_nv21_flip_vertically','_bgra8888_flip_vertically','_yuv420_grayscale','_nv21_grayscale','_bgra8888_grayscale','_yuv420_negate','_nv21_negate','_bgra8888_negate','_yuv420_crop_rect','_nv21_crop_rect','_bgra8888_crop_rect','_yuv420_rotate','_nv21_rotate','_bgra8888_rotate','_nvXX_to_nvYY','_yuv420_gaussblur','_nv21_gaussian_blur','_bgra8888_gaussian_blur','_yuv420_box_blur','_nv21_box_blur','_bgra8888_box_blur','_yuv420_mean_blur','_nv21_mean_blur','_bgra8888_mean_blur','_yuv420_from_rgba8888','_nv21_from_rgba8888','_bgra8888_from_rgba8888','_nv21_to_i420','_bgra8888_to_i420','_yuv420_i420_to_nv21','_bgra8888_to_nv21','_nv21_to_bgra8888','_yuv420_to_bgra8888']"
EXPORTED_RUNTIME_METHODS="['ccall','cwrap','HEAPU8','HEAP32']"

OUTPUT_JS="$OUT_DIR/yuv_ffi.js"

echo "== yuv_ffi WASM build =="
echo "Emcc:    $EMCC"
echo "Profile: $PROFILE"
echo "OutDir:  $OUT_DIR"
echo "Sources: $SOURCE_COUNT"

# xargs is used to safely pass all source files to emcc.
# We use NUL separators to avoid issues with spaces in paths.
find src -type f -name '*.c' ! -path '*/build/*' -print0 | \
  xargs -0 "$EMCC" \
    "$OPT_LEVEL" \
    -Isrc \
    -sWASM=1 \
    -sMODULARIZE=1 \
    -sEXPORT_NAME=createYuvFfiModule \
    -sALLOW_MEMORY_GROWTH=1 \
    -sENVIRONMENT=web \
    "-sEXPORTED_FUNCTIONS=$EXPORTED_FUNCTIONS" \
    "-sEXPORTED_RUNTIME_METHODS=$EXPORTED_RUNTIME_METHODS" \
    -o "$OUTPUT_JS"

echo "Build completed:"
echo " - $OUTPUT_JS"
echo " - $OUT_DIR/yuv_ffi.wasm"
