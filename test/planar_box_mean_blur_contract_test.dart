@Tags(['contract'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('zero-radius box blur is a no-op for I420 frames', () async {
    await YuvFfi.initialize();
    final image = YuvImage.i420(4, 4);
    final before = image.revision;

    expect(identical(image.applyBoxBlur(radius: 0), image), isTrue);
    expect(image.revision, before);
  });
}
