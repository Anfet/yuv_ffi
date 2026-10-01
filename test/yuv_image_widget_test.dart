@Tags(['contract'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('widget image-provider keys follow the image revision', () {
    final image = YuvImage.bgra(2, 2);
    final before = YuvImageProvider(image);
    expect(YuvImageProvider(image), before);

    image.markDirty();

    expect(YuvImageProvider(image), isNot(before));
  });
}
