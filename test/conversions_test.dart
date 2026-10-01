@Tags(['contract'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('current conversion methods return independent images in their target formats', () async {
    await YuvFfi.initialize();
    final source = YuvImage.fromRgbaBytes(
      Uint8List.fromList(<int>[0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255, 255, 255, 255, 255]),
      width: 2,
      height: 2,
      format: YuvPixelFormat.i420,
    );

    final nv12 = source.toNv12();
    final bgra = nv12.toBgra();

    expect(nv12.format, YuvPixelFormat.nv12);
    expect(bgra.format, YuvPixelFormat.bgra8888);
    expect(identical(source, nv12), isFalse);
    expect(identical(nv12, bgra), isFalse);
  });
}
