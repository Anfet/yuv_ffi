@Tags(['reference'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('native conversion round-trip retains frame geometry and BGRA storage size', () async {
    await YuvFfi.initialize();
    final source = YuvImage.fromRgbaBytes(
      Uint8List.fromList(<int>[10, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255, 100, 110, 120, 255]),
      width: 2,
      height: 2,
      format: YuvPixelFormat.i420,
    );
    final converted = source.toNv12().toI420().toBgra();

    expect(converted.size, source.size);
    expect(converted.toBgraBytes(), hasLength(16));
  });
}
