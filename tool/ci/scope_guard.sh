#!/usr/bin/env bash

# Prints the check keys required by the paths changed since <base>
# (committed, uncommitted and untracked): `bash tool/ci/scope_guard.sh <base-sha>`.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: scope_guard.sh <base-sha>\n' >&2
  exit 2
fi
base="$1"

path_keys() {
  case "$1" in
    *.md|doc/*|tasks/*)
      printf '\n'
      ;;
    lib/src/functions/bindings/*|ffigen.yaml|src/include/*)
      printf 'all\n'
      ;;
    .github/workflows/ci.yml)
      printf 'all\n'
      ;;
    .github/workflows/ci-smoke.yml)
      printf 'all\n'
      ;;
    .github/workflows/ci-vm.yml)
      printf 'vm\n'
      ;;
    .github/workflows/ci-windows.yml)
      printf 'windows\n'
      ;;
    .github/workflows/ci-macos.yml)
      printf 'macos\n'
      ;;
    .github/workflows/ci-ios.yml)
      printf 'ios\n'
      ;;
    .github/workflows/ci-android.yml)
      printf 'android\n'
      ;;
    .github/workflows/ci-linux.yml)
      printf 'linux\n'
      ;;
    .github/workflows/ci-web.yml)
      printf 'web\n'
      ;;
    .github/workflows/ci-example.yml)
      printf 'example\n'
      ;;
    .github/workflows/*)
      printf 'all\n'
      ;;
    tool/ci/_common.ps1|tool/ci/drive.ps1|tool/ci/drive.sh|tool/ci/smoke.ps1|tool/ci/scope_guard.sh)
      printf 'all\n'
      ;;
    tool/ci/vm.*)
      printf 'vm\n'
      ;;
    tool/ci/windows.*)
      printf 'windows\n'
      ;;
    tool/ci/macos.*)
      printf 'macos\n'
      ;;
    tool/ci/ios.*)
      printf 'ios\n'
      ;;
    tool/ci/android.*)
      printf 'android\n'
      ;;
    tool/ci/linux.*)
      printf 'linux\n'
      ;;
    tool/ci/web.*)
      printf 'web\n'
      ;;
    tool/ci/example.*)
      printf 'example\n'
      ;;
    tool/ci/*)
      printf 'all\n'
      ;;
    src/*|lib/src/yuv/impl/io/*|lib/src/functions/*|test/probe/*|example/integration_test/*|pubspec.yaml)
      printf 'all\n'
      ;;
    lib/src/yuv/impl/web/*|assets/wasm/*|tool/wasm/*)
      printf 'web\n'
      ;;
    darwin/*)
      printf 'ios macos\n'
      ;;
    windows/*|example/windows/*)
      printf 'windows\n'
      ;;
    example/macos/*)
      printf 'macos\n'
      ;;
    example/ios/*)
      printf 'ios\n'
      ;;
    android/*|example/android/*)
      printf 'android\n'
      ;;
    linux/*|example/linux/*)
      printf 'linux\n'
      ;;
    lib/*)
      printf 'vm example\n'
      ;;
    test/*|analysis_options.yaml|dart_test.yaml)
      printf 'vm\n'
      ;;
    example/*)
      printf 'example\n'
      ;;
    *)
      printf 'all\n'
      ;;
  esac
}

if ! changed_paths="$(git diff --no-renames --name-only "$base" -- && git ls-files --others --exclude-standard)"; then
  printf 'scope: could not enumerate changed paths since %s\n' "$base" >&2
  exit 1
fi

declare -A required=()
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  for key in $(path_keys "$path"); do
    required[$key]=1
  done
done <<< "$changed_paths"

if [[ -n "${required[all]:-}" ]]; then
  printf 'scope: all\n'
elif [[ ${#required[@]} -eq 0 ]]; then
  printf 'scope: none\n'
else
  printf 'scope: %s\n' "$(printf '%s\n' "${!required[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
fi
