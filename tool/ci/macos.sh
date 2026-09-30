#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../.." && pwd)"
native_build_directory="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/yuv-ffi-macos-native-build"

if [[ -z "${FLUTTER_ROOT:-}" ]]; then
  flutter_command="$(command -v flutter)"
  FLUTTER_ROOT="$(cd -- "$(dirname -- "$flutter_command")/.." && pwd)"
fi

cd "$repository_root"

cmake -S src -B "$native_build_directory" -DCMAKE_BUILD_TYPE=Release
cmake --build "$native_build_directory" --config Release
test -f "$native_build_directory/libyuv_ffi.dylib"

export DYLD_LIBRARY_PATH="$native_build_directory${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
cp "$native_build_directory/libyuv_ffi.dylib" \
  "$FLUTTER_ROOT/bin/cache/artifacts/engine/darwin-x64/libyuv_ffi.dylib"

flutter pub get
flutter test test/native_packaging_smoke_test.dart --reporter expanded

(
  cd example
  flutter pub get
  flutter build macos --release
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
