@Tags(['contract'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('named, generic and allocated factories expose current formats', () {
    final i420 = YuvImage.i420(3, 3);
    final nv12 = YuvImage.nv12(3, 3);
    final bgra = YuvImage.bgra(3, 3);
    final generic = YuvImage(YuvPixelFormat.nv12, 3, 3);
    final rgba = YuvImage.fromRgbaBytes(Uint8List(3 * 3 * 4), width: 3, height: 3, format: YuvPixelFormat.i420);

    expect(
      [i420.format, nv12.format, bgra.format, generic.format, rgba.format],
      [YuvPixelFormat.i420, YuvPixelFormat.nv12, YuvPixelFormat.bgra8888, YuvPixelFormat.nv12, YuvPixelFormat.i420],
    );
    expect(YuvImage.allocate(YuvPixelFormat.bgra8888, 3, 3).toBytes(), everyElement(0));
  });
}
