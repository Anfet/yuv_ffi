#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../.." && pwd)"
native_build_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
native_build_directory="$(mktemp -d "$native_build_parent/yuv-ffi-macos-native-build.XXXXXX")"
command_log="$(mktemp "${TMPDIR:-/tmp}/yuv-ffi-ci.XXXXXX")"

run_quiet() {
  local started ended elapsed
  started="$(date +%s)"
  if "$@" >"$command_log" 2>&1; then
    ended="$(date +%s)"
    elapsed=$((ended - started))
    if [[ "${YUV_CI_VERBOSE:-}" == 1 ]]; then cat "$command_log"; fi
    printf 'ok %s (%s s)\n' "$*" "$elapsed"
  else
    local status=$?
    printf '%s failed with exit code %s\n' "$*" "$status" >&2
    if [[ "${YUV_CI_VERBOSE:-}" == 1 ]]; then cat "$command_log" >&2; else tail -n 80 "$command_log" >&2; fi
    return "$status"
  fi
}
trap 'rm -f "$command_log"' EXIT

for tool_directory in /opt/homebrew/bin /usr/local/bin; do
  if [[ -d "$tool_directory" ]]; then
    PATH="$tool_directory:$PATH"
  fi
done
export PATH

if [[ -z "${FLUTTER_ROOT:-}" ]]; then
  flutter_command="$(command -v flutter || true)"
  if [[ -n "$flutter_command" ]]; then
    FLUTTER_ROOT="$(cd -- "$(dirname -- "$flutter_command")/.." && pwd)"
  elif [[ -x "$HOME/storage/flutter_3.44/flutter/bin/flutter" ]]; then
    FLUTTER_ROOT="$HOME/storage/flutter_3.44/flutter"
  else
    echo 'Flutter was not found on PATH or at ~/storage/flutter_3.44/flutter.' >&2
    exit 1
  fi
fi
export FLUTTER_ROOT
PATH="$FLUTTER_ROOT/bin:$PATH"
export PATH

cd "$repository_root"

run_quiet cmake -S src -B "$native_build_directory" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES='arm64;x86_64'
run_quiet cmake --build "$native_build_directory" --config Release
test -f "$native_build_directory/libyuv_ffi.dylib"

export DYLD_LIBRARY_PATH="$native_build_directory${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
cp "$native_build_directory/libyuv_ffi.dylib" \
  "$FLUTTER_ROOT/bin/cache/artifacts/engine/darwin-x64/libyuv_ffi.dylib"

run_quiet flutter pub get
flutter test --no-pub --reporter json test/native_packaging_smoke_test.dart | dart tool/ci/test_report.dart

(
  cd example
  run_quiet flutter pub get
  run_quiet flutter build macos --release
)

env DYLD_LIBRARY_PATH= bash tool/ci/drive.sh \
  integration_test/native_app_runtime_smoke_test.dart macos

shopt -s nullglob
targets=(example/integration_test/*_native_test.dart)
if (( ${#targets[@]} == 0 )); then
  echo 'No native integration-test targets were found.' >&2
  exit 1
fi

for target_path in "${targets[@]}"; do
  env DYLD_LIBRARY_PATH= bash tool/ci/drive.sh "${target_path#example/}" macos
done
