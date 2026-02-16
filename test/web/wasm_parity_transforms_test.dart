import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  if (!kIsWeb) {
    test('web transform parity tests are skipped on non-web runtime', () {
      expect(true, isTrue);
    });
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await YuvFfi.ensureInitialized();
  });

  test('crop on BGRA is exact', () {
    const w = 8;
    const h = 6;
    final rgba = _buildRgbaPattern(w, h);
    final bgraBefore = _rgbaToBgra(rgba);

    final image = YuvImage.bgra(w, h)..fromRgba8888(rgba);
    image.crop(const ui.Rect.fromLTWH(2, 1, 3, 4));
    final out = image.toBgra8888();

    final expected = _cropBgra(bgraBefore, w, 2, 1, 3, 4);
    expect(image.width, 3);
    expect(image.height, 4);
    expect(out, orderedEquals(expected));
  });

  test('rotate 90 on BGRA is exact', () {
    const w = 6;
    const h = 4;
    final rgba = _buildRgbaPattern(w, h);
    final bgraBefore = _rgbaToBgra(rgba);

    final image = YuvImage.bgra(w, h)..fromRgba8888(rgba);
    image.rotate(YuvImageRotation.rotation90);
    final out = image.toBgra8888();

    final expected = _rotate90CwBgra(bgraBefore, w, h);
    expect(image.width, h);
    expect(image.height, w);
    expect(out, orderedEquals(expected));
  });

  test('flipHorizontal and flipVertical on BGRA are exact', () {
    const w = 7;
    const h = 5;
    final rgba = _buildRgbaPattern(w, h);
    final bgraBefore = _rgbaToBgra(rgba);

    final imageH = YuvImage.bgra(w, h)..fromRgba8888(rgba);
    imageH.flipHorizontally();
    expect(imageH.toBgra8888(), orderedEquals(_flipHorizontalBgra(bgraBefore, w, h)));

    final imageV = YuvImage.bgra(w, h)..fromRgba8888(rgba);
    imageV.flipVertically();
    expect(imageV.toBgra8888(), orderedEquals(_flipVerticalBgra(bgraBefore, w, h)));
  });

  test('swapNv is reversible', () {
    const w = 16;
    const h = 10;
    final rgba = _buildRgbaPattern(w, h);
    final image = YuvImage.nv21(w, h)..fromRgba8888(rgba);
    final originalU = Uint8List.fromList(image.uPlane.bytes);

    final swapped = image.swapNv();
    final restored = swapped.swapNv();

    expect(restored.width, w);
    expect(restored.height, h);
    expect(restored.uPlane.bytes, orderedEquals(originalU));
  });
}

Uint8List _buildRgbaPattern(int width, int height) {
  final out = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      out[i] = (x * 9 + y * 3) & 0xFF;
      out[i + 1] = (x * 5 + y * 11) & 0xFF;
      out[i + 2] = (x * 13 + y * 7) & 0xFF;
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

Uint8List _cropBgra(
  Uint8List src,
  int srcWidth,
  int left,
  int top,
  int cropWidth,
  int cropHeight,
) {
  final out = Uint8List(cropWidth * cropHeight * 4);
  for (int y = 0; y < cropHeight; y++) {
    for (int x = 0; x < cropWidth; x++) {
      final sx = left + x;
      final sy = top + y;
      final dstIdx = (y * cropWidth + x) * 4;
      final srcIdx = (sy * srcWidth + sx) * 4;
      out.setRange(dstIdx, dstIdx + 4, src, srcIdx);
    }
  }
  return out;
}

Uint8List _rotate90CwBgra(Uint8List src, int width, int height) {
  final out = Uint8List(width * height * 4);
  final dstWidth = height;
  for (int y = 0; y < width; y++) {
    for (int x = 0; x < height; x++) {
      final sx = y;
      final sy = height - 1 - x;
      final dstIdx = (y * dstWidth + x) * 4;
      final srcIdx = (sy * width + sx) * 4;
      out.setRange(dstIdx, dstIdx + 4, src, srcIdx);
    }
  }
  return out;
}

Uint8List _flipHorizontalBgra(Uint8List src, int width, int height) {
  final out = Uint8List(src.length);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final sx = width - 1 - x;
      final dstIdx = (y * width + x) * 4;
      final srcIdx = (y * width + sx) * 4;
      out.setRange(dstIdx, dstIdx + 4, src, srcIdx);
    }
  }
  return out;
}

Uint8List _flipVerticalBgra(Uint8List src, int width, int height) {
  final out = Uint8List(src.length);
  for (int y = 0; y < height; y++) {
    final sy = height - 1 - y;
    for (int x = 0; x < width; x++) {
      final dstIdx = (y * width + x) * 4;
      final srcIdx = (sy * width + x) * 4;
      out.setRange(dstIdx, dstIdx + 4, src, srcIdx);
    }
  }
  return out;
}
