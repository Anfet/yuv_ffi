@Tags(['contract'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('copy is independent and keeps the current format and geometry', () {
    final source = YuvImage.nv12(4, 2);
    final copied = source.copy();

    expect(identical(copied, source), isFalse);
    expect(copied.format, YuvPixelFormat.nv12);
    expect(copied.size, source.size);
  });
}
