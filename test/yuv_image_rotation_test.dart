@Tags(['contract'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('rotation values expose quarter-turn geometry and inverse navigation', () {
    expect(YuvImageRotation.rotation0.degrees, 0);
    expect(YuvImageRotation.rotation90.swapSize, isTrue);
    expect(YuvImageRotation.rotation180.swapSize, isFalse);
    expect(YuvImageRotation.rotation270.clockwise, YuvImageRotation.rotation0);
    for (final value in YuvImageRotation.values) {
      expect(value.clockwise.counterClockwise, value);
    }
  });
}
