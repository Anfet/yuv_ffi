#!/usr/bin/env bash

set -euo pipefail

event_name="${GITHUB_EVENT_NAME:-}"
prefix="${GITHUB_REF_NAME:-$(git branch --show-current)}"

if [[ "$event_name" == "workflow_dispatch" || "$event_name" == "pull_request" ||
  "$prefix" == "main" || "$prefix" == release/* ]]; then
  exit 0
fi

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

prefix_tokens="+$prefix"
covers_key() {
  local key="$1"
  [[ "$prefix_tokens" == *"+all/"* || "$prefix_tokens" == *"+all+"* ||
    "$prefix_tokens" == *"+$key/"* || "$prefix_tokens" == *"+$key+"* ]]
}

if ! base="$(git merge-base dev HEAD)"; then
  printf 'scope: could not determine merge base against dev\n' >&2
  exit 1
fi

if ! changed_paths="$(mktemp)"; then
  printf 'scope: could not create a temporary path list\n' >&2
  exit 1
fi
trap 'rm -f "$changed_paths"' EXIT

if ! git diff --no-renames --name-only -z "$base" HEAD > "$changed_paths"; then
  printf 'scope: could not enumerate changed paths\n' >&2
  exit 1
fi

while IFS= read -r -d '' path; do
  [[ -n "$path" ]] || continue
  keys="$(path_keys "$path")"
  [[ -n "$keys" ]] || continue
  for key in $keys; do
    if ! covers_key "$key"; then
      printf "scope: branch prefix '%s' does not cover %s required by %s\n" \
        "$prefix" "$keys" "$path" >&2
      exit 1
    fi
  done
done < "$changed_paths"
