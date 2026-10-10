#!/usr/bin/env bash

# FFI bindings regeneration and audit, run on a Mac with Xcode:
# `bash tool/ci/bindings.sh` from the package root of a clean copy of the
# exact commit (a git checkout or a `git archive` extraction).
#
# Regenerates lib/src/functions/bindings/yuv_ffi_bingings.dart from
# ffigen.yaml with the active Xcode libclang, audits the generated members
# against their Dart usage, and fails on any drift from the committed
# ffigen.yaml or bindings. A drift is a failure to report, never a file to
# commit from this script: the copy is left with the regenerated output.

set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../.." && pwd)"
committed_directory="$(mktemp -d "${TMPDIR:-/tmp}/yuv-ffi-bindings.XXXXXX")"
trap 'rm -rf "$committed_directory"' EXIT

bindings_path='lib/src/functions/bindings/yuv_ffi_bingings.dart'

if [[ "$(uname -s)" != Darwin ]]; then
  echo 'tool/ci/bindings.sh must run on macOS with Xcode.' >&2
  exit 1
fi

for tool_directory in /opt/homebrew/bin /usr/local/bin; do
  if [[ -d "$tool_directory" ]]; then
    PATH="$tool_directory:$PATH"
  fi
done

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

for tool in git xcode-select flutter dart; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required tool is missing: $tool." >&2
    exit 1
  fi
done

xcode_developer="$(xcode-select -p)"
libclang="$xcode_developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/libclang.dylib"
if [[ ! -f "$libclang" ]]; then
  echo "libclang is missing from the active Xcode: $libclang" >&2
  exit 1
fi
export FFIGEN_LIBCLANG_PATH="$libclang"
echo "libclang: $libclang"

cd "$repository_root"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
  [[ "$(git rev-parse --show-toplevel)" == "$(pwd -P)" ]] &&
  [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo 'Tracked files are modified: run in a clean copy of the exact commit.' >&2
  git status --porcelain --untracked-files=no >&2
  exit 1
fi

cp ffigen.yaml "$committed_directory/ffigen.yaml"
cp "$bindings_path" "$committed_directory/yuv_ffi_bingings.dart"

flutter --version
flutter pub get
dart run ffigen --config ffigen.yaml
dart run tool/verify_bindings_audit.dart

drift=0
git diff --no-index --exit-code -- "$committed_directory/ffigen.yaml" ffigen.yaml || drift=1
git diff --no-index --exit-code -- "$committed_directory/yuv_ffi_bingings.dart" "$bindings_path" || drift=1
if (( drift != 0 )); then
  echo 'The regenerated bindings differ from the committed files.' >&2
  exit 1
fi

echo 'Bindings check passed: regeneration matches the committed ffigen.yaml and bindings; audit passed.'
