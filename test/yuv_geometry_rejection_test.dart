@Tags(['contract'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('factories reject non-positive image geometry', () {
    expect(() => YuvImage.i420(0, 2), throwsArgumentError);
    expect(() => YuvImage.nv12(2, 0), throwsArgumentError);
    expect(() => YuvImage.allocate(YuvPixelFormat.bgra8888, -1, 2), throwsArgumentError);
  });
}
