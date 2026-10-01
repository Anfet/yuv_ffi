@Tags(['contract'])
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
    await YuvFfi.initialize();
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
      ..applyGrayscale()
      // ignore: deprecated_member_use_from_same_package
      ..applyBlackWhite()
      // ignore: deprecated_member_use_from_same_package
      ..applyNegate()
      // ignore: deprecated_member_use_from_same_package
      ..applyFlipHorizontal()
      // ignore: deprecated_member_use_from_same_package
      ..applyFlipVertical();

    // ignore: deprecated_member_use_from_same_package
    expect(image.toBgraBytes().length, 16);
  });

  test('i420/nv21/bgra pipelines run without throwing', () {
    final rgba = Uint8List(8 * 6 * 4);
    // ignore: deprecated_member_use_from_same_package
    final i420 = YuvImage.i420(8, 6)..applyRgbaBytes(rgba);
    // ignore: deprecated_member_use_from_same_package
    final nv21 = YuvImage.nv12(8, 6)..applyRgbaBytes(rgba);
    // ignore: deprecated_member_use_from_same_package
    final bgra = YuvImage.bgra(8, 6)..applyRgbaBytes(rgba);

    i420
      // ignore: deprecated_member_use_from_same_package
      ..applyGaussianBlur(radius: 2, sigma: 2)
      // ignore: deprecated_member_use_from_same_package
      ..applyBoxBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..applyMeanBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..applyGrayscale()
      // ignore: deprecated_member_use_from_same_package
      ..applyBlackWhite()
      // ignore: deprecated_member_use_from_same_package
      ..applyNegate();
    nv21
      // ignore: deprecated_member_use_from_same_package
      ..applyGaussianBlur(radius: 2, sigma: 2)
      // ignore: deprecated_member_use_from_same_package
      ..applyBoxBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..applyMeanBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..applyGrayscale()
      // ignore: deprecated_member_use_from_same_package
      ..applyBlackWhite()
      // ignore: deprecated_member_use_from_same_package
      ..applyNegate();
    bgra
      // ignore: deprecated_member_use_from_same_package
      ..applyGaussianBlur(radius: 2, sigma: 2)
      // ignore: deprecated_member_use_from_same_package
      ..applyBoxBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..applyMeanBlur(radius: 2)
      // ignore: deprecated_member_use_from_same_package
      ..applyGrayscale()
      // ignore: deprecated_member_use_from_same_package
      ..applyBlackWhite()
      // ignore: deprecated_member_use_from_same_package
      ..applyNegate();

    // ignore: deprecated_member_use_from_same_package
    expect(i420.toBgraBytes().length, 8 * 6 * 4);
    // ignore: deprecated_member_use_from_same_package
    expect(nv21.toBgraBytes().length, 8 * 6 * 4);
    // ignore: deprecated_member_use_from_same_package
    expect(bgra.toBgraBytes().length, 8 * 6 * 4);
  });
}
