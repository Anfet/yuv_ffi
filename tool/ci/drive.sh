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
  "$@" >"$output_file" 2>&1
drive_exit_code=${PIPESTATUS[0]}
set -e

if (( drive_exit_code != 0 )); then
  marker_line="$(grep -n -m1 -E 'FAILED|EXCEPTION|Error' "$output_file" | cut -d: -f1 || true)"
  if [[ -n "$marker_line" ]]; then sed -n "${marker_line},$((marker_line + 199))p" "$output_file"; else tail -n 200 "$output_file"; fi
  echo "flutter drive failed for $target on $device with exit code $drive_exit_code" >&2
  exit "$drive_exit_code"
fi

if ! grep -Fq 'All tests passed' "$output_file"; then
  marker_line="$(grep -n -m1 -E 'FAILED|EXCEPTION|Error' "$output_file" | cut -d: -f1 || true)"
  if [[ -n "$marker_line" ]]; then sed -n "${marker_line},$((marker_line + 199))p" "$output_file"; else tail -n 200 "$output_file"; fi
  echo "flutter drive completed for $target on $device without the required All tests passed verdict" >&2
  exit 1
fi

if [[ "$target" == "integration_test/camera_source_web_smoke_test.dart" ]]; then
  grep -F 'CI3_DIAGNOSTICS ' "$output_file" || true
fi

echo "PASS $target on $device"
