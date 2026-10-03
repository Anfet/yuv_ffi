import 'dart:math' as math;
import 'dart:typed_data';

import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// A shader-readable RGBA texture packed from a YUV frame's visible samples.
final class YuvPlanesTexture {
  /// RGBA texture bytes with [bytesPerTexel] consecutive source bytes in each
  /// texel; with three, the alpha byte is 255.
  final Uint8List bytes;

  /// Texture dimensions in texels and rows.
  final int width, height;

  /// Source bytes per texel: 4, or 3 to keep samples out of alpha where the
  /// renderer premultiplies sampled colors (CanvasKit).
  final int bytesPerTexel;

  /// U sample location: texture row, first byte, and byte step.
  final ({int row, int offset, int step}) u;

  /// V sample location: texture row, first byte, and byte step.
  final ({int row, int offset, int step}) v;

  const YuvPlanesTexture._({
    required this.bytes,
    required this.width,
    required this.height,
    required this.bytesPerTexel,
    required this.u,
    required this.v,
  });

  /// Copies [frame] into a shader texture, or returns `null` when its layout
  /// requires the caller's BGRA fallback.
  ///
  /// [bytesPerTexel] must be 3 or 4.
  static YuvPlanesTexture? pack(YuvImage frame, {int bytesPerTexel = 4}) {
    if (bytesPerTexel != 3 && bytesPerTexel != 4) {
      throw ArgumentError.value(bytesPerTexel, 'bytesPerTexel', 'must be 3 or 4');
    }
    final y = frame.yPlane;
    if (y.pixelStride != 1) {
      return null;
    }

    final chromaWidth = (frame.width + 1) ~/ 2;
    final chromaHeight = (frame.height + 1) ~/ 2;
    return switch (frame.format) {
      YuvPixelFormat.i420 => _packI420(frame, chromaWidth, chromaHeight, bytesPerTexel),
      YuvPixelFormat.nv12 => _packNv12(frame, chromaWidth, chromaHeight, bytesPerTexel),
      YuvPixelFormat.bgra8888 => null,
    };
  }

  static YuvPlanesTexture? _packI420(YuvImage frame, int chromaWidth, int chromaHeight, int bytesPerTexel) {
    final u = frame.uPlane;
    final v = frame.vPlane;
    if (u.pixelStride != v.pixelStride || (u.pixelStride != 1 && u.pixelStride != 2)) {
      return null;
    }

    final byteWidth = math.max(frame.width, u.pixelStride == 1 ? chromaWidth * 2 : chromaWidth * 2 - 1);
    final textureWidth = (byteWidth + bytesPerTexel - 1) ~/ bytesPerTexel;
    final textureHeight = frame.height + (u.pixelStride == 1 ? chromaHeight : chromaHeight * 2);
    if (textureWidth > 4096 || textureHeight > 4096) {
      return null;
    }

    final rowStride = textureWidth * bytesPerTexel;
    final texture = Uint8List(rowStride * textureHeight);
    _copyY(frame, texture, rowStride);
    if (u.pixelStride == 1) {
      for (var row = 0; row < chromaHeight; row++) {
        final target = (frame.height + row) * rowStride;
        texture.setRange(target, target + chromaWidth, u.bytes, row * u.rowStride);
        texture.setRange(target + chromaWidth, target + chromaWidth * 2, v.bytes, row * v.rowStride);
      }
      return YuvPlanesTexture._(
        bytes: _toRgba(texture, bytesPerTexel),
        width: textureWidth,
        height: textureHeight,
        bytesPerTexel: bytesPerTexel,
        u: (row: frame.height, offset: 0, step: 1),
        v: (row: frame.height, offset: chromaWidth, step: 1),
      );
    }

    _copyChromaRows(
      source: u,
      target: texture,
      targetRow: frame.height,
      rows: chromaHeight,
      byteLength: chromaWidth * 2 - 1,
      targetRowStride: rowStride,
    );
    _copyChromaRows(
      source: v,
      target: texture,
      targetRow: frame.height + chromaHeight,
      rows: chromaHeight,
      byteLength: chromaWidth * 2 - 1,
      targetRowStride: rowStride,
    );
    return YuvPlanesTexture._(
      bytes: _toRgba(texture, bytesPerTexel),
      width: textureWidth,
      height: textureHeight,
      bytesPerTexel: bytesPerTexel,
      u: (row: frame.height, offset: 0, step: 2),
      v: (row: frame.height + chromaHeight, offset: 0, step: 2),
    );
  }

  static YuvPlanesTexture? _packNv12(YuvImage frame, int chromaWidth, int chromaHeight, int bytesPerTexel) {
    final chroma = frame.uPlane;
    if (chroma.pixelStride != 2) {
      return null;
    }

    final byteWidth = math.max(frame.width, chromaWidth * 2);
    final textureWidth = (byteWidth + bytesPerTexel - 1) ~/ bytesPerTexel;
    final textureHeight = frame.height + chromaHeight;
    if (textureWidth > 4096 || textureHeight > 4096) {
      return null;
    }

    final rowStride = textureWidth * bytesPerTexel;
    final texture = Uint8List(rowStride * textureHeight);
    _copyY(frame, texture, rowStride);
    for (var row = 0; row < chromaHeight; row++) {
      final target = (frame.height + row) * rowStride;
      texture.setRange(target, target + chromaWidth * 2, chroma.bytes, row * chroma.rowStride);
    }
    return YuvPlanesTexture._(
      bytes: _toRgba(texture, bytesPerTexel),
      width: textureWidth,
      height: textureHeight,
      bytesPerTexel: bytesPerTexel,
      u: (row: frame.height, offset: 0, step: 2),
      v: (row: frame.height, offset: 1, step: 2),
    );
  }

  static Uint8List _toRgba(Uint8List packed, int bytesPerTexel) {
    if (bytesPerTexel == 4) {
      return packed;
    }
    final texels = packed.length ~/ 3;
    final rgba = Uint8List(texels * 4);
    for (var texel = 0, source = 0, target = 0; texel < texels; texel++, source += 3, target += 4) {
      rgba[target] = packed[source];
      rgba[target + 1] = packed[source + 1];
      rgba[target + 2] = packed[source + 2];
      rgba[target + 3] = 255;
    }
    return rgba;
  }

  static void _copyY(YuvImage frame, Uint8List target, int targetRowStride) {
    final y = frame.yPlane;
    for (var row = 0; row < frame.height; row++) {
      final targetOffset = row * targetRowStride;
      final sourceOffset = row * y.rowStride;
      target.setRange(targetOffset, targetOffset + frame.width, y.bytes, sourceOffset);
    }
  }

  static void _copyChromaRows({
    required YuvPlane source,
    required Uint8List target,
    required int targetRow,
    required int rows,
    required int byteLength,
    required int targetRowStride,
  }) {
    for (var row = 0; row < rows; row++) {
      final sourceOffset = row * source.rowStride;
      final targetOffset = (targetRow + row) * targetRowStride;
      target.setRange(targetOffset, targetOffset + byteLength, source.bytes, sourceOffset);
    }
  }
}
