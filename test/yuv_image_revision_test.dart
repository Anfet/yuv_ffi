@Tags(['contract'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('manual invalidation changes the revision while direct plane writes do not', () {
    final image = YuvImage.bgra(2, 2);
    final initial = image.revision;
    image.yPlane.bytes[0] = 1;
    expect(image.revision, initial);
    image.markDirty();
    expect(image.revision, initial + 1);
  });
}
