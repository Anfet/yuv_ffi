@Tags(['contract'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('allocation and RGBA factory reject invalid sizes before native work', () {
    expect(() => YuvImage.allocate(YuvPixelFormat.i420, 0, 1), throwsArgumentError);
    expect(() => YuvImage.fromRgbaBytes(Uint8List(3), width: 1, height: 1, format: YuvPixelFormat.bgra8888), throwsArgumentError);
  });
}
