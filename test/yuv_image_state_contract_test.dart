@Tags(['contract'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('applyPlanes atomically replaces valid data and rejects invalid geometry', () {
    final image = YuvImage.bgra(2, 2);
    final replacement = YuvPlane(2, 8, 4, Uint8List.fromList(List<int>.generate(16, (index) => index)));
    image.applyPlanes([replacement]);
    expect(image.toBytes(), orderedEquals(replacement.bytes));

    final before = image.toBytes();
    expect(() => image.applyPlanes([YuvPlane(2, 4, 4)]), throwsArgumentError);
    expect(image.toBytes(), orderedEquals(before));
  });
}
