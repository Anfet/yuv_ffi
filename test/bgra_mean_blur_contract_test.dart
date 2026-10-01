@Tags(['contract'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('zero-radius mean blur is a no-op for BGRA frames', () async {
    await YuvFfi.initialize();
    final image = YuvImage.bgra(4, 4);
    final before = image.revision;

    expect(identical(image.applyMeanBlur(radius: 0), image), isTrue);
    expect(image.revision, before);
  });
}
