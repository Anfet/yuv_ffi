@Tags(['contract'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('plane aliases describe the current row and pixel strides', () {
    final plane = YuvPlane(2, 12, 4);
    expect(plane.bytesPerRow, 12);
    expect(plane.bytesPerPixel, 4);
  });
}
