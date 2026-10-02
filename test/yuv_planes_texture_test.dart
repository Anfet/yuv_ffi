@Tags(['contract'])
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/widgets/yuv_planes_texture.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  for (final size in <(int, int)>[(1, 1), (3, 5), (33, 17), (720, 480)]) {
    for (final pixelStride in <int>[1, 2]) {
      test('packs I420 ${size.$1}x${size.$2} with chroma stride $pixelStride', () {
        final frame = _i420(size.$1, size.$2, pixelStride);
        final texture = YuvPlanesTexture.pack(frame)!;
        _expectSamples(texture, frame);
        final before = texture.bytes[0];
        frame.yPlane.bytes[0] ^= 0xff;
        expect(texture.bytes[0], before);
      });
    }
    test('packs NV12 ${size.$1}x${size.$2}', () {
      final frame = _nv12(size.$1, size.$2);
      _expectSamples(YuvPlanesTexture.pack(frame)!, frame);
    });
  }

  test('returns null for unsupported layouts and oversized textures', () {
    expect(YuvPlanesTexture.pack(YuvImage.bgra(1, 1)), isNull);
    expect(YuvPlanesTexture.pack(YuvImage.i420(2, 2, yPixelStride: 2)), isNull);
    expect(YuvPlanesTexture.pack(YuvImage.i420(2, 2, uvPixelStride: 3)), isNull);
    expect(YuvPlanesTexture.pack(YuvImage.i420(1, 4097)), isNull);
  });

  test('copies Android I420 chroma rows without per-sample repacking', () {
    final frame = _i420(3, 5, 2);
    final texture = YuvPlanesTexture.pack(frame)!;
    const byteLength = 3;
    for (final (plane, firstTextureRow) in [(frame.uPlane, frame.height), (frame.vPlane, frame.height + frame.uPlane.height)]) {
      for (var row = 0; row < plane.height; row++) {
        final sourceOffset = row * plane.rowStride;
        final textureOffset = (firstTextureRow + row) * texture.width * 4;
        expect(texture.bytes.sublist(textureOffset, textureOffset + byteLength), plane.bytes.sublist(sourceOffset, sourceOffset + byteLength));
      }
    }
  });
}

void _expectSamples(YuvPlanesTexture texture, YuvImage frame) {
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      expect(_textureByte(texture, y, x), frame.yPlane.bytes[y * frame.yPlane.rowStride + x]);
      final chromaX = x ~/ 2;
      final chromaY = y ~/ 2;
      expect(_textureByte(texture, texture.u.row + chromaY, texture.u.offset + chromaX * texture.u.step), _u(frame, chromaX, chromaY));
      expect(_textureByte(texture, texture.v.row + chromaY, texture.v.offset + chromaX * texture.v.step), _v(frame, chromaX, chromaY));
    }
  }
}

int _textureByte(YuvPlanesTexture texture, int row, int byte) => texture.bytes[(row * texture.width + byte ~/ 4) * 4 + byte % 4];

int _u(YuvImage frame, int x, int y) => frame.uPlane.bytes[y * frame.uPlane.rowStride + x * frame.uPlane.pixelStride];

int _v(YuvImage frame, int x, int y) => switch (frame.format) {
  YuvPixelFormat.i420 => frame.vPlane.bytes[y * frame.vPlane.rowStride + x * frame.vPlane.pixelStride],
  YuvPixelFormat.nv12 => frame.uPlane.bytes[y * frame.uPlane.rowStride + x * frame.uPlane.pixelStride + 1],
  YuvPixelFormat.bgra8888 => throw StateError('Not YUV.'),
};

YuvImage _i420(int width, int height, int chromaPixelStride) {
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  return YuvImage.i420(
    width,
    height,
    planes: [
      _plane(height, width + 3, 1, 10),
      _plane(chromaHeight, chromaWidth * chromaPixelStride + 2, chromaPixelStride, 80),
      _plane(chromaHeight, chromaWidth * chromaPixelStride + 2, chromaPixelStride, 160),
    ],
    layout: YuvPlaneLayout.preserve,
  );
}

YuvImage _nv12(int width, int height) {
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  return YuvImage.nv12(
    width,
    height,
    planes: [_plane(height, width + 3, 1, 10), _plane(chromaHeight, chromaWidth * 2 + 2, 2, 80)],
    layout: YuvPlaneLayout.preserve,
  );
}

YuvPlane _plane(int height, int rowStride, int pixelStride, int seed) {
  final bytes = Uint8List(height * rowStride);
  for (var row = 0; row < height; row++) {
    for (var byte = 0; byte < rowStride; byte++) {
      bytes[row * rowStride + byte] = (seed + row * 17 + byte) & 0xff;
    }
  }
  return YuvPlane(height, rowStride, pixelStride, bytes);
}
