@Tags(['contract'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('preserve retains declared padding while packed removes it', () {
    final plane = YuvPlane(2, 12, 4, Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 9, 9, 10, 11, 12, 13, 14, 15, 16, 17, 9, 9, 9, 9]));
    final preserved = YuvImage.bgra(2, 2, planes: [plane], layout: YuvPlaneLayout.preserve);
    final packed = YuvImage.bgra(2, 2, planes: [plane], layout: YuvPlaneLayout.packed);

    expect(preserved.yPlane.rowStride, 12);
    expect(packed.yPlane.rowStride, 8);
    expect(packed.toBytes(), orderedEquals(<int>[1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17]));
  });
}
