#!/usr/bin/env bash

set -euo pipefail

if (( $# < 2 )); then
  echo "Usage: $0 <integration-test-target> <device> [flutter-drive-arguments...]" >&2
  exit 64
fi

target="$1"
device="$2"
shift 2

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/../.." && pwd)"
output_file="$(mktemp "${TMPDIR:-/tmp}/yuv-ffi-drive.XXXXXX")"

cleanup() {
  rm -f "$output_file"
}
trap cleanup EXIT

cd "$repository_root/example"

set +e
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target="$target" \
  -d "$device" \
  "$@" 2>&1 | tee "$output_file"
drive_exit_code=${PIPESTATUS[0]}
set -e

if (( drive_exit_code != 0 )); then
  echo "flutter drive failed for $target on $device with exit code $drive_exit_code" >&2
  exit "$drive_exit_code"
fi

if ! grep -Fq 'All tests passed' "$output_file"; then
  echo "flutter drive completed for $target on $device without the required All tests passed verdict" >&2
  exit 1
fi

echo "PASS $target on $device"
