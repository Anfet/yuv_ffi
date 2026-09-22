import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Demonstrates the chroma byte order actually produced by each path that
/// writes an NV interleaved plane.
///
/// The project contract keeps the public name `nv21` while the real byte order
/// is UV (NV12-like). This test pins the order down with a saturated color, so
/// U and V are far apart and a swap cannot hide behind a small delta.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  const int w = 4;
  const int h = 4;

  /// Solid red: strongly negative U, strongly positive V.
  Uint8List solidRedRgba() {
    final rgba = Uint8List(w * h * 4);
    for (int i = 0; i < rgba.length; i += 4) {
      rgba[i] = 255; // R
      rgba[i + 1] = 0; // G
      rgba[i + 2] = 0; // B
      rgba[i + 3] = 255; // A
    }
    return rgba;
  }

  /// BT.601 studio-range references for pure red.
  /// U = -38*255 >> 8 + 128 ~= 90, V = 112*255 >> 8 + 128 ~= 240.
  const int expectedU = 90;
  const int expectedV = 240;
  const int tolerance = 3;

  group('NV chroma byte order', () {
    test('RGBA -> NV21 writes the same chroma order as BGRA -> NV21', () {
      final direct = YuvImage.nv21(w, h)..fromRgba8888(solidRedRgba());

      // The BGRA route reaches NV through yuv_convert_v1, which is the order
      // every other converter agrees on.
      final viaBgra = YuvImage.bgra(w, h)
        ..fromRgba8888(solidRedRgba())
        ..toYuvNv21();

      final directFirst = direct.uPlane.bytes[0];
      final directSecond = direct.uPlane.bytes[1];
      final bgraFirst = viaBgra.uPlane.bytes[0];
      final bgraSecond = viaBgra.uPlane.bytes[1];

      // The two routes round differently (direct RGBA averaging versus a
      // BGRA intermediate), so they are compared with a coarse tolerance. What
      // must match is which of U and V lands in which byte: a swap shows up as
      // a ~150 difference, far outside this bound.
      const orderTolerance = 16;

      expect(
        directFirst,
        closeTo(bgraFirst, orderTolerance),
        reason: 'first chroma byte differs: RGBA->NV gives $directFirst, BGRA->NV gives $bgraFirst',
      );
      expect(
        directSecond,
        closeTo(bgraSecond, orderTolerance),
        reason: 'second chroma byte differs: RGBA->NV gives $directSecond, BGRA->NV gives $bgraSecond',
      );
    });

    test('the interleaved plane stores (U, V), matching every reader', () {
      final image = YuvImage.nv21(w, h)..fromRgba8888(solidRedRgba());

      // Conversion out of NV reads byte 0 as U and byte 1 as V, so a writer
      // must follow the same order.
      expect(image.uPlane.bytes[0], closeTo(expectedU, tolerance), reason: 'byte 0 of the chroma pair must be U (~$expectedU for red)');
      expect(image.uPlane.bytes[1], closeTo(expectedV, tolerance), reason: 'byte 1 of the chroma pair must be V (~$expectedV for red)');
    });

    test('RGBA -> NV21 -> I420 lands U and V in the correct planes', () {
      final image = YuvImage.nv21(w, h)
        ..fromRgba8888(solidRedRgba())
        ..toYuvI420();

      expect(image.uPlane.bytes[0], closeTo(expectedU, tolerance), reason: 'U plane must hold the U sample');
      expect(image.vPlane.bytes[0], closeTo(expectedV, tolerance), reason: 'V plane must hold the V sample');
    });

    test('RGBA -> NV21 -> BGRA round-trip preserves red', () {
      final image = YuvImage.nv21(w, h)..fromRgba8888(solidRedRgba());
      final bgra = image.toBgra8888();

      // BGRA byte order is B, G, R, A. Swapped chroma turns red into blue.
      expect(bgra[2], greaterThan(180), reason: 'red channel lost: chroma order is swapped somewhere');
      expect(bgra[0], lessThan(80), reason: 'blue channel raised: chroma order is swapped somewhere');
    });
  }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
