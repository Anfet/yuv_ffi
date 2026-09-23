import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-03 on Web: `YuvImage.nv12` accepts an explicit interleaved
/// chroma `pixelStride` above the packed-pair minimum as a real gap, and a
/// WASM ABI v1 operation walking that plane through its declared strides
/// leaves the gap byte untouched.
///
/// Mirrors the IO-side coverage in `test/yuv_image_factories_test.dart`; this
/// file runs the same shape of check against the WASM backend.
void main() {
  if (!kIsWeb) {
    test('nv12 pixel-gap Web parity test is skipped on non-web runtime', () {
      expect(true, isTrue);
    });
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await YuvFfi.ensureInitialized();
  });

  test('a real WASM ABI v1 operation on a gapped NV12 plane leaves the gap byte untouched', () {
    // uvPixelStride 3 on a 4x4 image: uvWidth=2, so each chroma row is
    // [U0 V0 gap][U1 V1 gap] = 6 bytes, rowStride 6.
    const gapMarker = 0xEE;
    final chroma = Uint8List(2 * 6);
    for (int row = 0; row < 2; row++) {
      final base = row * 6;
      chroma[base + 0] = 10; // U0
      chroma[base + 1] = 20; // V0
      chroma[base + 2] = gapMarker; // gap
      chroma[base + 3] = 30; // U1
      chroma[base + 4] = 40; // V1
      chroma[base + 5] = gapMarker; // gap
    }
    final image = YuvImage.nv12(4, 4, planes: [YuvPlane(4, 4), YuvPlane(2, 6, 3, chroma)]);

    // grayscale() is a pure effect: same format/geometry in and out, so any
    // corruption of the gap bytes could only come from the WASM kernel
    // treating the plane as tightly packed instead of walking it through its
    // declared strides.
    image.grayscale();

    for (int row = 0; row < 2; row++) {
      final base = row * 6;
      expect(image.uPlane.bytes[base + 2], gapMarker, reason: 'row $row pixel 0 gap byte was touched');
      expect(image.uPlane.bytes[base + 5], gapMarker, reason: 'row $row pixel 1 gap byte was touched');
    }
  });
}
