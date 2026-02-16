import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  if (!kIsWeb) {
    test('web conversion parity tests are skipped on non-web runtime', () {
      expect(true, isTrue);
    });
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await YuvFfi.ensureInitialized();
  });

  test('BGRA -> I420 -> BGRA round-trip keeps acceptable quality', () {
    const w = 96;
    const h = 64;
    final rgba = _buildRgbaPattern(w, h);
    final expectedBgra = _rgbaToBgra(rgba);

    final image = YuvImage.i420(w, h)..fromRgba8888(rgba);
    final outBgra = image.toBgra8888();

    expect(_mae(outBgra, expectedBgra), lessThan(20.0));
  });

  test('BGRA -> NV21 -> BGRA round-trip keeps acceptable quality', () {
    const w = 96;
    const h = 64;
    final rgba = _buildRgbaPattern(w, h);
    final expectedBgra = _rgbaToBgra(rgba);

    final image = YuvImage.nv21(w, h)..fromRgba8888(rgba);
    final outBgra = image.toBgra8888();

    expect(_mae(outBgra, expectedBgra), lessThan(55.0));
  });

  test('I420 <-> NV21 conversion round-trip keeps dimensions and quality', () {
    const w = 96;
    const h = 64;
    final rgba = _buildRgbaPattern(w, h);
    final expectedBgra = _rgbaToBgra(rgba);

    final i420 = YuvImage.i420(w, h)..fromRgba8888(rgba);
    final nv21 = i420.toYuvNv21();
    final back = nv21.toYuvI420();
    final outBgra = back.toBgra8888();

    expect(nv21.width, w);
    expect(nv21.height, h);
    expect(back.width, w);
    expect(back.height, h);
    expect(_mae(outBgra, expectedBgra), lessThan(25.0));
  });

  test('toYuvBgra8888 returns valid BGRA image', () {
    const w = 48;
    const h = 32;
    final rgba = _buildRgbaPattern(w, h);
    final nv21 = YuvImage.nv21(w, h)..fromRgba8888(rgba);

    final bgra = nv21.toYuvBgra8888();
    expect(bgra.format, YuvFileFormat.bgra8888);
    expect(bgra.width, w);
    expect(bgra.height, h);
    expect(bgra.yPlane.bytes.length, w * h * 4);
  });
}

Uint8List _buildRgbaPattern(int width, int height) {
  final out = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      out[i] = (x * 3 + y * 5) & 0xFF;
      out[i + 1] = (x * 7 + y * 11) & 0xFF;
      out[i + 2] = (x * 13 + y * 17) & 0xFF;
      out[i + 3] = 255;
    }
  }
  return out;
}

Uint8List _rgbaToBgra(Uint8List rgba) {
  final out = Uint8List(rgba.length);
  for (int i = 0; i < rgba.length; i += 4) {
    out[i] = rgba[i + 2];
    out[i + 1] = rgba[i + 1];
    out[i + 2] = rgba[i];
    out[i + 3] = rgba[i + 3];
  }
  return out;
}

double _mae(Uint8List a, Uint8List b) {
  int sum = 0;
  for (int i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}
