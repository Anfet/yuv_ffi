#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifact_root="$repo_root/test/reference/test_pattern_512/artifacts"
libyuv_commit="2dd4257364d39c38d79465c4ddc4b93137fe729b"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/yuv_ffi-libyuv.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT

command -v clang++ >/dev/null || { echo "FAILED: clang++ is required." >&2; exit 127; }
command -v sips >/dev/null || { echo "FAILED: sips is required to decode PNG references." >&2; exit 127; }

libyuv_root="$work_root/libyuv"
decoded_root="$work_root/decoded"
git clone --quiet https://chromium.googlesource.com/libyuv/libyuv.git "$libyuv_root"
git -C "$libyuv_root" checkout --quiet --detach "$libyuv_commit"
actual_commit="$(git -C "$libyuv_root" rev-parse HEAD)"
if [[ "$actual_commit" != "$libyuv_commit" ]]; then
  echo "FAILED: libyuv commit is $actual_commit, expected $libyuv_commit." >&2
  exit 1
fi

mkdir -p "$decoded_root"
for artifact in i420_decoded.png nv21_uv_decoded.png rotate_90.png rotate_180.png rotate_270.png flip_horizontal.png flip_vertical.png crop_inner.png crop_1x1.png crop_3x5.png crop_127x255.png; do
  sips -s format bmp "$artifact_root/$artifact" --out "$decoded_root/$artifact.bmp" >/dev/null
done

clang++ -std=c++17 -O0 -g0 -w -I "$libyuv_root/include" \
  -DLIBYUV_DISABLE_X86 -DLIBYUV_DISABLE_SME -DLIBYUV_DISABLE_NEON -DLIBYUV_DISABLE_SVE \
  "$repo_root/tool/oracle/libyuv_harness.cc" \
  "$libyuv_root"/source/{convert,convert_from_argb,row_common,planar_functions,cpu_id,scale,scale_common,rotate,rotate_common,row_any,scale_any,rotate_any,convert_argb,convert_from,scale_argb,scale_uv,scale_rgb,video_common}.cc \
  -o "$work_root/libyuv_harness"

fixture_artifacts="$artifact_root"
if [[ "${ORACLE_CORRUPT_I420:-0}" == "1" ]]; then
  fixture_artifacts="$work_root/corrupted-artifacts"
  cp -R "$artifact_root" "$fixture_artifacts"
  printf '\0' | dd of="$fixture_artifacts/source_i420.yuv" bs=1 count=1 conv=notrunc status=none
fi

"$work_root/libyuv_harness" "$fixture_artifacts" "$decoded_root"
