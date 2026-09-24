import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  if (!kIsWeb) {
    test('web-only wasm tests are skipped on non-web runtime', () {
      expect(true, isTrue);
    });
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // ignore: deprecated_member_use_from_same_package
    await YuvFfi.ensureInitialized();
  });

  test('bgra unary ops via wasm do not throw', () {
    final image = YuvImage.bgra(
      2,
      2,
      planes: [
        YuvPlane(2, 8, 4, Uint8List.fromList([1, 2, 3, 10, 11, 12, 13, 20, 21, 22, 23, 30, 31, 32, 33, 40])),
      ],
    );

    image
      // ignore: deprecated_member_use_from_same_package
      ..grayscale()
      // ignore: deprecated_member_use_from_same_package
      ..blackwhite()
      // ignore: deprecated_member_use_from_same_package
      ..negate()
      // ignore: deprecated_member_use_from_same_package
      ..flipHorizontally()
      // ignore: deprecated_member_use_from_same_package
      ..flipVertically();

    // ignore: deprecated_member_use_from_same_package
    expect(image.toBgra8888().length, 16);
  });

  test('i420/nv21/bgra pipelines run without throwing', () {
    final rgba = Uint8List(8 * 6 * 4);
    // ignore: deprecated_member_use_from_same_package
    final i420 = YuvImage.i420(8, 6)..fromRgba8888(rgba);
    // ignore: deprecated_member_use_from_same_package
    final nv21 = YuvImage.nv21(8, 6)..fromRgba8888(rgba);
    // ignore: deprecated_member_use_from_same_package
    final bgra = YuvImage.bgra(8, 6)..fromRgba8888(rgba);

    i420
      // ignore: deprecated_member_use_from_same_package
      ..gaussianBlur(radius: 2, sigma: 2)
      // ignore: deprecated_member_use_from_same_package
      ..boxBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..meanBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..grayscale()
      // ignore: deprecated_member_use_from_same_package
      ..blackwhite()
      // ignore: deprecated_member_use_from_same_package
      ..negate();
    nv21
      // ignore: deprecated_member_use_from_same_package
      ..gaussianBlur(radius: 2, sigma: 2)
      // ignore: deprecated_member_use_from_same_package
      ..boxBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..meanBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..grayscale()
      // ignore: deprecated_member_use_from_same_package
      ..blackwhite()
      // ignore: deprecated_member_use_from_same_package
      ..negate();
    bgra
      // ignore: deprecated_member_use_from_same_package
      ..gaussianBlur(radius: 2, sigma: 2)
      // ignore: deprecated_member_use_from_same_package
      ..boxBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..meanBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..grayscale()
      // ignore: deprecated_member_use_from_same_package
      ..blackwhite()
      // ignore: deprecated_member_use_from_same_package
      ..negate();

    // ignore: deprecated_member_use_from_same_package
    expect(i420.toBgra8888().length, 8 * 6 * 4);
    // ignore: deprecated_member_use_from_same_package
    expect(nv21.toBgra8888().length, 8 * 6 * 4);
    // ignore: deprecated_member_use_from_same_package
    expect(bgra.toBgra8888().length, 8 * 6 * 4);
  });
}
