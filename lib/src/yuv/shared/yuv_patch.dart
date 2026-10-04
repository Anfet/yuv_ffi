import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Opaque, unscaled patch insertion for a [YuvImage].
extension YuvImagePatch on YuvImage {
  /// Copies all visible samples of [fragment] into this image at ([x], [y]).
  ///
  /// Both images must have the same format and the fragment must fit fully.
  /// I420 and NV12 insertions start on an even coordinate; an odd fragment
  /// extent is allowed only when it reaches the matching image edge. Padding
  /// and pixel-gap bytes are preserved. A successful insertion advances this
  /// image's revision exactly once and leaves [fragment] unchanged.
  YuvImage applyPatch(YuvImage fragment, {required int x, required int y}) {
    _validatePatch(this, fragment, x, y);

    final specs = _planeSpecs(format, fragment.width, fragment.height, x, y);
    final targets = List<YuvPlane>.of(planes);
    final sources = List<YuvPlane>.of(fragment.planes);
    if (targets.length != specs.length || sources.length != specs.length) {
      throw ArgumentError('Image plane count does not match its pixel format');
    }
    for (int i = 0; i < specs.length; i++) {
      _validatePlane(targets[i], specs[i], target: true);
      _validatePlane(sources[i], specs[i], target: false);
    }
    for (final target in targets) {
      for (final source in sources) {
        if (identical(target.bytes.buffer, source.bytes.buffer) &&
            target.bytes.offsetInBytes < source.bytes.offsetInBytes + source.bytes.lengthInBytes &&
            source.bytes.offsetInBytes < target.bytes.offsetInBytes + target.bytes.lengthInBytes) {
          throw ArgumentError('Patch source and destination must not share byte storage');
        }
      }
    }
    for (int i = 0; i < specs.length; i++) {
      _copyPlane(targets[i], sources[i], specs[i]);
    }
    YuvRevision.bump(this);
    return this;
  }
}

void _validatePlane(YuvPlane plane, _PlanePatch patch, {required bool target}) {
  final x = target ? patch.x : 0;
  final y = target ? patch.y : 0;
  if (plane.height < y + patch.height || plane.pixelStride < patch.sampleBytes) {
    throw ArgumentError('Image plane geometry is too small for the patch');
  }
  final lastByteInRow = (x + patch.width - 1) * plane.pixelStride + patch.sampleBytes;
  final lastRowEnd = (y + patch.height - 1) * plane.rowStride + lastByteInRow;
  if (plane.rowStride < lastByteInRow || plane.bytes.lengthInBytes < lastRowEnd) {
    throw ArgumentError('Image plane bytes are too short for the patch');
  }
}

void _validatePatch(YuvImage target, YuvImage fragment, int x, int y) {
  if (fragment.format != target.format) {
    throw ArgumentError('Patch format must match the destination format');
  }
  if (identical(fragment, target)) {
    throw ArgumentError('Patch source and destination must be different images');
  }
  if (x < 0 || y < 0) {
    throw ArgumentError('Patch coordinates must not be negative');
  }
  if (x > target.width - fragment.width || y > target.height - fragment.height) {
    throw ArgumentError('Patch must fit fully inside the destination bounds');
  }
  if (target.format == YuvPixelFormat.bgra8888) return;
  if (x.isOdd || y.isOdd) {
    throw ArgumentError('YUV patch coordinates must follow chroma 2x2 alignment');
  }
  if (fragment.width.isOdd && x + fragment.width != target.width) {
    throw ArgumentError('An odd YUV patch width must reach the right edge for chroma 2x2 alignment');
  }
  if (fragment.height.isOdd && y + fragment.height != target.height) {
    throw ArgumentError('An odd YUV patch height must reach the bottom edge for chroma 2x2 alignment');
  }
}

List<_PlanePatch> _planeSpecs(YuvPixelFormat format, int width, int height, int x, int y) => switch (format) {
  YuvPixelFormat.i420 => <_PlanePatch>[
    _PlanePatch(width, height, x, y, 1),
    _PlanePatch((width + 1) ~/ 2, (height + 1) ~/ 2, x ~/ 2, y ~/ 2, 1),
    _PlanePatch((width + 1) ~/ 2, (height + 1) ~/ 2, x ~/ 2, y ~/ 2, 1),
  ],
  YuvPixelFormat.nv12 => <_PlanePatch>[_PlanePatch(width, height, x, y, 1), _PlanePatch((width + 1) ~/ 2, (height + 1) ~/ 2, x ~/ 2, y ~/ 2, 2)],
  YuvPixelFormat.bgra8888 => <_PlanePatch>[_PlanePatch(width, height, x, y, 4)],
};

void _copyPlane(YuvPlane target, YuvPlane source, _PlanePatch patch) {
  final contiguous = target.pixelStride == patch.sampleBytes && source.pixelStride == patch.sampleBytes;
  for (int row = 0; row < patch.height; row++) {
    final sourceRow = row * source.rowStride;
    final targetRow = (patch.y + row) * target.rowStride + patch.x * target.pixelStride;
    if (contiguous) {
      target.bytes.setRange(targetRow, targetRow + patch.width * patch.sampleBytes, source.bytes, sourceRow);
      continue;
    }
    for (int column = 0; column < patch.width; column++) {
      final sourceOffset = sourceRow + column * source.pixelStride;
      final targetOffset = targetRow + column * target.pixelStride;
      target.bytes.setRange(targetOffset, targetOffset + patch.sampleBytes, source.bytes, sourceOffset);
    }
  }
}

final class _PlanePatch {
  const _PlanePatch(this.width, this.height, this.x, this.y, this.sampleBytes);

  final int width;
  final int height;
  final int x;
  final int y;
  final int sampleBytes;
}
