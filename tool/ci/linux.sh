#!/usr/bin/env bash

# Linux native checks, run directly on an Ubuntu machine with a display server
# available through xvfb-run: `bash tool/ci/linux.sh` from the package root.
#
# 1. Clang CTest with BUILD_TESTING in Debug and Release (ASan/UBSan/LSan and
#    the malloc --wrap allocation-failure group), then the sanitizer case count.
# 2. The native library built and resolved by its installed name through
#    LD_LIBRARY_PATH for the packaging smoke test.
# 3. The Linux example in Release, the app-runtime smoke test and every
#    example/integration_test/*_native_test.dart target through drive.sh.
#
# The checkout is not modified: CMake build directories and a copy of the
# candidate (where the Linux runner is scaffolded) live in a temporary
# directory. The script installs no system packages; a missing tool fails
# with its name.

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../.." && pwd)"
work_directory="$(mktemp -d "${TMPDIR:-/tmp}/yuv-ffi-linux.XXXXXX")"
command_log="$work_directory/command.log"

cleanup() {
  rm -rf "$work_directory"
}
trap cleanup EXIT

run_quiet() {
  local started ended
  started="$(date +%s)"
  if "$@" >"$command_log" 2>&1; then
    ended="$(date +%s)"
    if [[ "${YUV_CI_VERBOSE:-}" == 1 ]]; then cat "$command_log"; fi
    printf 'ok %s (%s s)\n' "$*" "$((ended - started))"
  else
    local status=$?
    printf '%s failed with exit code %s\n' "$*" "$status" >&2
    if [[ "${YUV_CI_VERBOSE:-}" == 1 ]]; then cat "$command_log" >&2; else tail -n 80 "$command_log" >&2; fi
    return "$status"
  fi
}

if [[ "$(uname -s)" != Linux ]]; then
  echo 'tool/ci/linux.sh must run on Linux.' >&2
  exit 1
fi

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

missing=()
for tool in clang cmake ninja pkg-config xvfb-run flutter dart cmp; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if (( ${#missing[@]} > 0 )); then
  echo "Required tools are missing: ${missing[*]}. Prepare the machine (see MACHINES.md); this script installs nothing." >&2
  exit 1
fi
if ! pkg-config --exists gtk+-3.0; then
  echo 'Required package is missing: gtk+-3.0 (libgtk-3-dev).' >&2
  exit 1
fi

flutter --version
clang --version
cmake --version

# 1. Native CTest with sanitizers, Debug and Release.
for build_type in Debug Release; do
  build_directory="$work_directory/sanitizer-$build_type"
  run_quiet cmake -S "$repository_root" -B "$build_directory" \
    -DCMAKE_BUILD_TYPE="$build_type" -DBUILD_TESTING=ON -DCMAKE_C_COMPILER=clang
  run_quiet cmake --build "$build_directory" --config "$build_type" --parallel
  ctest --test-dir "$build_directory" -C "$build_type" --output-on-failure
done

sanitizer_output="$work_directory/sanitizer-count.log"
"$work_directory/sanitizer-Debug/test_native/abi_sanitizer_test" | tee "$sanitizer_output" | tail -n 3
if grep -Fq 'SKIPPED' "$sanitizer_output"; then
  echo 'The sanitizer test skipped a case group: the malloc --wrap allocation-failure injection did not run.' >&2
  exit 1
fi
if ! grep -Eq '^checks: [1-9][0-9]*, failures: 0, executed cases: [1-9][0-9]*$' "$sanitizer_output"; then
  echo 'The sanitizer test did not report a non-empty passing case count.' >&2
  exit 1
fi

# 2. Native library resolved by its installed name: packaging smoke.
native_build_directory="$work_directory/native-build"
run_quiet cmake -S "$repository_root/src" -B "$native_build_directory" -DCMAKE_BUILD_TYPE=Release
run_quiet cmake --build "$native_build_directory" --config Release --parallel
test -f "$native_build_directory/libyuv_ffi.so"

# A copy of the candidate keeps the checkout unchanged: pub get, the scaffolded
# Linux runner and the build output stay in the temporary directory.
candidate_root="$work_directory/candidate"
mkdir -p "$candidate_root"
tar -C "$repository_root" \
  --exclude=./.git --exclude=./build --exclude=./.dart_tool \
  --exclude=./example/build --exclude=./example/.dart_tool --exclude=./example/linux \
  -cf - . | tar -C "$candidate_root" -xf -

cd "$candidate_root"
run_quiet flutter pub get
LD_LIBRARY_PATH="$native_build_directory${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  flutter test --no-pub --reporter json test/native_packaging_smoke_test.dart | dart tool/ci/test_report.dart

# 3. Linux example in Release, app-runtime smoke and native integration targets.
# `flutter create` replaces pubspec.lock with a template lock even with
# --no-pub; the committed lock is restored and must not drift after pub get.
cd "$candidate_root/example"
cp pubspec.lock "$work_directory/pubspec.lock.committed"
run_quiet flutter config --enable-linux-desktop
run_quiet flutter create --platforms=linux --no-pub .
cp "$work_directory/pubspec.lock.committed" pubspec.lock
run_quiet flutter pub get
if ! cmp -s "$work_directory/pubspec.lock.committed" pubspec.lock; then
  echo 'example/pubspec.lock drifted after flutter pub get on Linux:' >&2
  diff -u "$work_directory/pubspec.lock.committed" pubspec.lock >&2 || true
  exit 1
fi
run_quiet flutter build linux --release
cd "$candidate_root"

xvfb-run -a bash tool/ci/drive.sh integration_test/native_app_runtime_smoke_test.dart linux

shopt -s nullglob
targets=(example/integration_test/*_native_test.dart)
if (( ${#targets[@]} == 0 )); then
  echo 'No native integration-test targets were found.' >&2
  exit 1
fi
for target_path in "${targets[@]}"; do
  xvfb-run -a bash tool/ci/drive.sh "${target_path#example/}" linux
done

echo "Linux checks passed: CTest Debug and Release with sanitizers; packaging smoke; Linux Release build; app-runtime smoke; native targets=${#targets[@]}."
