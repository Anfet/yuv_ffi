@Tags(['contract'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  test('native ABI operations process current public methods', () async {
    await YuvFfi.initialize();
    final image = YuvImage.fromRgbaBytes(Uint8List(4 * 4 * 4), width: 4, height: 4, format: YuvPixelFormat.i420);

    final nv12 = image.toNv12();
    final before = nv12.revision;
    expect(identical(nv12.applyChromaSwap(), nv12), isTrue);
    expect(nv12.revision, before + 1);
    expect(nv12.toI420().toBgra().toBgraBytes(), hasLength(4 * 4 * 4));
  });
}
