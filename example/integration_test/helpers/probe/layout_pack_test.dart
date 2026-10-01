@Tags(['probe'])
library;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'probe_seed.dart';

void main() {
  test('packing preserves the visible BGRA result across padded and gapped layouts', () async {
    await YuvFfi.initialize();
    for (final format in YuvPixelFormat.values) {
      for (final size in const [(1, 1), (2, 2), (3, 5), (16, 9), (33, 17), (127, 255)]) {
        for (final layout in const ['tight', 'padded', 'gap']) {
          final preserved = _makeImage(format, size.$1, size.$2, layout, YuvPlaneLayout.preserve);
          final baseline = preserved.toBgraBytes();
          preserved.pack();
          expect(preserved.toBgraBytes(), orderedEquals(baseline), reason: '$format ${size.$1}x${size.$2} $layout');
          expect(preserved.isTightlyPacked, isTrue, reason: '$format ${size.$1}x${size.$2} $layout');

          final defaultPacked = _makeImage(format, size.$1, size.$2, layout, YuvPlaneLayout.packed);
          expect(defaultPacked.toBgraBytes(), orderedEquals(baseline), reason: '$format ${size.$1}x${size.$2} packed default $layout');
          expect(defaultPacked.isTightlyPacked, isTrue, reason: '$format ${size.$1}x${size.$2} packed default $layout');
        }
      }
    }
  });
}

YuvImage _makeImage(YuvPixelFormat format, int width, int height, String layout, YuvPlaneLayout packing) {
  var seed = 12345 + width * 31 + height;
  int nextByte() {
    seed = probeNextSeed(seed);
    return (seed >> 8) & 0xff;
  }

  Uint8List fill(int length) => Uint8List.fromList(List<int>.generate(length, (_) => nextByte()));
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  final padding = layout == 'padded' ? 7 : 0;
  switch (format) {
    case YuvPixelFormat.i420:
      final pixelStride = layout == 'gap' ? 2 : 1;
      final yStride = width * pixelStride + padding;
      final uvStride = chromaWidth * pixelStride + padding;
      return YuvImage.i420(
        width,
        height,
        yPixelStride: pixelStride,
        uvPixelStride: pixelStride,
        planes: [
          YuvPlane(height, yStride, pixelStride, fill(height * yStride)),
          YuvPlane(chromaHeight, uvStride, pixelStride, fill(chromaHeight * uvStride)),
          YuvPlane(chromaHeight, uvStride, pixelStride, fill(chromaHeight * uvStride)),
        ],
        layout: packing,
      );
    case YuvPixelFormat.nv12:
      final pixelStride = layout == 'gap' ? 3 : 2;
      final yStride = width + padding;
      final uvStride = (chromaWidth - 1) * pixelStride + 2 + padding;
      return YuvImage.nv12(
        width,
        height,
        uvPixelStride: pixelStride,
        planes: [YuvPlane(height, yStride, 1, fill(height * yStride)), YuvPlane(chromaHeight, uvStride, pixelStride, fill(chromaHeight * uvStride))],
        layout: packing,
      );
    case YuvPixelFormat.bgra8888:
      final pixelStride = layout == 'gap' ? 5 : 4;
      final rowStride = (width - 1) * pixelStride + 4 + padding;
      return YuvImage.bgra(width, height, planes: [YuvPlane(height, rowStride, pixelStride, fill(height * rowStride))], layout: packing);
  }
}
