#!/usr/bin/env sh
#
# YUV-12: copies the PNG-only subset of the native reference fixtures
# (test/reference/test_pattern_512/) into example/assets/, since Flutter
# cannot bundle assets that live outside the package root and the example
# app needs them to run reference_web_conversions_test.dart.
#
# Only the manifest, the source PNG, and the PNG artifacts are copied. The
# raw .bin/.yuv blobs listed in the manifest are intentionally NOT copied:
# neither the native suite (test/reference_native_conversions_test.dart) nor
# its Web port ever reads them from disk -- expected raw plane bytes are
# always recomputed in pure Dart from the source PNG. Copying them here
# would add ~2.8 MB of dead weight to the example package and to git.
#
# Re-run this script whenever the upstream fixtures change (new cases,
# regenerated artifacts, manifest edits) and commit the resulting diff under
# example/assets/reference/ alongside the upstream change.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXAMPLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$EXAMPLE_DIR/.." && pwd)"

SOURCE_FIXTURE_DIR="$REPO_ROOT/test/reference/test_pattern_512"
SOURCE_IMAGE="$REPO_ROOT/test/assets/test_pattern_512.png"

DEST_DIR="$EXAMPLE_DIR/assets/reference"
DEST_FIXTURE_DIR="$DEST_DIR/test_pattern_512"

if [ ! -f "$SOURCE_FIXTURE_DIR/manifest.json" ]; then
  echo "manifest not found: $SOURCE_FIXTURE_DIR/manifest.json" >&2
  exit 1
fi

rm -rf "$DEST_FIXTURE_DIR"
mkdir -p "$DEST_FIXTURE_DIR/artifacts"

cp "$SOURCE_FIXTURE_DIR/manifest.json" "$DEST_FIXTURE_DIR/manifest.json"
cp "$SOURCE_IMAGE" "$DEST_DIR/test_pattern_512.png"

# ! -path '*/build/*' has no meaning here (there is no build/ under
# artifacts/), this is a plain PNG-only copy.
for png in "$SOURCE_FIXTURE_DIR"/artifacts/*.png; do
  cp "$png" "$DEST_FIXTURE_DIR/artifacts/"
done

echo "Copied fixtures to $DEST_DIR"

PROBE_SOURCE_DIR="$REPO_ROOT/test/probe"
PROBE_DEST_DIR="$EXAMPLE_DIR/integration_test/helpers/probe"
PROBE_GOLDEN_DEST="$EXAMPLE_DIR/assets/probe"

rm -rf "$PROBE_DEST_DIR"
mkdir -p "$PROBE_DEST_DIR" "$PROBE_GOLDEN_DEST"
cp -R "$PROBE_SOURCE_DIR"/. "$PROBE_DEST_DIR"/
rm -f "$PROBE_DEST_DIR"/operation_coverage_test.dart \
  "$PROBE_DEST_DIR"/android_release_benchmark_contract_test.dart \
  "$PROBE_DEST_DIR"/baseline/windows-13th-gen-intel-r-core-tm-i9-13980hx-x64-release.json \
  "$PROBE_DEST_DIR"/probe_copy_sync_test.dart \
  "$PROBE_DEST_DIR"/probe_performance_test.dart \
  "$PROBE_DEST_DIR"/probe_runner.dart \
  "$PROBE_DEST_DIR"/probe_runner_test.dart \
  "$PROBE_DEST_DIR"/probe_scenarios.dart \
  "$PROBE_DEST_DIR"/release_probe_core_test.dart \
  "$PROBE_DEST_DIR"/windows_release_package_provenance_contract_test.dart
cp "$PROBE_SOURCE_DIR/golden.json" "$PROBE_GOLDEN_DEST/golden.json"

echo "Copied operation probes to $PROBE_DEST_DIR and $PROBE_GOLDEN_DEST"
