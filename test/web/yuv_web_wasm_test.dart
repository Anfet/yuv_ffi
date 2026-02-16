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
    await YuvFfi.ensureInitialized();
  });

  test('bgra unary ops via wasm do not throw', () {
    final image = YuvImage.bgra(
      2,
      2,
      planes: [
        YuvPlane(
          2,
          8,
          4,
          Uint8List.fromList([
            1, 2, 3, 10,
            11, 12, 13, 20,
            21, 22, 23, 30,
            31, 32, 33, 40,
          ]),
        ),
      ],
    );

    image
      ..grayscale()
      ..blackwhite()
      ..negate()
      ..flipHorizontally()
      ..flipVertically();

    expect(image.toBgra8888().length, 16);
  });

  test('i420/nv21/bgra pipelines run without throwing', () {
    final rgba = Uint8List(8 * 6 * 4);
    final i420 = YuvImage.i420(8, 6)..fromRgba8888(rgba);
    final nv21 = YuvImage.nv21(8, 6)..fromRgba8888(rgba);
    final bgra = YuvImage.bgra(8, 6)..fromRgba8888(rgba);

    i420
      ..gaussianBlur(radius: 2, sigma: 2)
      ..boxBlur(radius: 2)
      ..meanBlur(radius: 2)
      ..grayscale()
      ..blackwhite()
      ..negate();
    nv21
      ..gaussianBlur(radius: 2, sigma: 2)
      ..boxBlur(radius: 2)
      ..meanBlur(radius: 2)
      ..grayscale()
      ..blackwhite()
      ..negate();
    bgra
      ..gaussianBlur(radius: 2, sigma: 2)
      ..boxBlur(radius: 2)
      ..meanBlur(radius: 2)
      ..grayscale()
      ..blackwhite()
      ..negate();

    expect(i420.toBgra8888().length, 8 * 6 * 4);
    expect(nv21.toBgra8888().length, 8 * 6 * 4);
    expect(bgra.toBgra8888().length, 8 * 6 * 4);
  });
}
