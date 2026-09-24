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
