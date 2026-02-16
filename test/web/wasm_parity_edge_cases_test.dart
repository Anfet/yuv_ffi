import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  if (!kIsWeb) {
    test('web edge-case parity tests are skipped on non-web runtime', () {
      expect(true, isTrue);
    });
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await YuvFfi.ensureInitialized();
  });

  test('odd-size conversion parity envelope holds for 1x1, 3x5, 127x255', () {
    const sizes = <({int w, int h})>[
      (w: 1, h: 1),
      (w: 3, h: 5),
      (w: 127, h: 255),
    ];

    for (final s in sizes) {
      final rgba = _buildRgbaPattern(s.w, s.h);
      final expectedBgra = _rgbaToBgra(rgba);

      final i420 = YuvImage.i420(s.w, s.h)..fromRgba8888(rgba);
      final nv21 = YuvImage.nv21(s.w, s.h)..fromRgba8888(rgba);
      final bgra = YuvImage.bgra(s.w, s.h)..fromRgba8888(rgba);

      final i420Bgra = i420.toBgra8888();
      final nv21Bgra = nv21.toBgra8888();
      final bgraOut = bgra.toBgra8888();

      expect(i420Bgra.length, s.w * s.h * 4);
      expect(nv21Bgra.length, s.w * s.h * 4);
      expect(bgraOut.length, s.w * s.h * 4);
      expect(_mae(i420Bgra, expectedBgra), lessThan(40.0));
      expect(_mae(nv21Bgra, expectedBgra), lessThan(75.0));
      expect(bgraOut, orderedEquals(expectedBgra));
    }
  });

  test('fromRgba8888 validates input length consistently', () {
    const w = 8;
    const h = 4;
    final bad = Uint8List(w * h * 4 - 1);
    final images = <YuvImage>[
      YuvImage.i420(w, h),
      YuvImage.nv21(w, h),
      YuvImage.bgra(w, h),
    ];

    for (final image in images) {
      expect(() => image.fromRgba8888(bad), throwsArgumentError);
    }
  });

  test('I420 custom rowStride/pixelStride produces same BGRA output as baseline', () {
    const w = 17;
    const h = 11;
    final rgba = _buildRgbaPattern(w, h);
    final baseline = YuvImage.i420(w, h)..fromRgba8888(rgba);

    final uvW = (w / 2).ceil();
    final uvH = (h / 2).ceil();

    final yPadded = _copyPlaneWithPadding(
      source: baseline.yPlane,
      logicalWidth: w,
      logicalHeight: h,
      dstRowStride: w + 7,
      dstPixelStride: 1,
    );
    final uPadded = _copyPlaneWithPadding(
      source: baseline.uPlane,
      logicalWidth: uvW,
      logicalHeight: uvH,
      dstRowStride: uvW * 2 + 5,
      dstPixelStride: 2,
    );
    final vPadded = _copyPlaneWithPadding(
      source: baseline.vPlane,
      logicalWidth: uvW,
      logicalHeight: uvH,
      dstRowStride: uvW * 2 + 5,
      dstPixelStride: 2,
    );

    final custom = YuvImage.i420(w, h, planes: [yPadded, uPadded, vPadded]);

    expect(custom.toBgra8888(), orderedEquals(baseline.toBgra8888()));
  });

  test('NV21 custom rowStride/pixelStride produces same BGRA output as baseline', () {
    const w = 19;
    const h = 13;
    final rgba = _buildRgbaPattern(w, h);
    final baseline = YuvImage.nv21(w, h)..fromRgba8888(rgba);

    final yPadded = _copyPlaneWithPadding(
      source: baseline.yPlane,
      logicalWidth: w,
      logicalHeight: h,
      dstRowStride: w + 11,
      dstPixelStride: 1,
    );
    final uvPadded = _copyUvInterleavedPlaneWithPadding(
      source: baseline.uPlane,
      logicalRowBytes: baseline.uPlane.rowStride,
      logicalHeight: baseline.uPlane.height,
      dstRowStride: baseline.uPlane.rowStride + 9,
      dstPixelStride: 2,
    );

    final custom = YuvImage.nv21(w, h, planes: [yPadded, uvPadded]);

    expect(custom.toBgra8888(), orderedEquals(baseline.toBgra8888()));
  });

  test('crop clamps out-of-bounds rect and keeps deterministic output', () {
    const w = 9;
    const h = 7;
    final rgba = _buildRgbaPattern(w, h);
    final sourceBgra = _rgbaToBgra(rgba);

    final fullClamp = YuvImage.bgra(w, h)..fromRgba8888(rgba);
    fullClamp.crop(const ui.Rect.fromLTWH(-3.2, -2.4, 20.1, 20.8));
    expect(fullClamp.width, w);
    expect(fullClamp.height, h);
    expect(fullClamp.toBgra8888(), orderedEquals(sourceBgra));

    final partial = YuvImage.bgra(w, h)..fromRgba8888(rgba);
    partial.crop(const ui.Rect.fromLTWH(6.2, 4.3, 8.8, 6.7));
    expect(partial.width, 3);
    expect(partial.height, 3);
    expect(partial.toBgra8888(), orderedEquals(_cropBgra(sourceBgra, w, 6, 4, 3, 3)));
  });

  test('odd-size transform chains stay stable across formats', () {
    const w = 31;
    const h = 17;
    final rgba = _buildRgbaPattern(w, h);

    final images = <YuvImage>[
      YuvImage.i420(w, h)..fromRgba8888(rgba),
      YuvImage.nv21(w, h)..fromRgba8888(rgba),
      YuvImage.bgra(w, h)..fromRgba8888(rgba),
    ];

    for (final image in images) {
      image
        ..rotate(YuvImageRotation.rotation90)
        ..crop(const ui.Rect.fromLTWH(2, 1, 10, 7))
        ..flipHorizontally()
        ..flipVertically()
        ..boxBlur(radius: 2)
        ..meanBlur(radius: 2)
        ..gaussianBlur(radius: 1, sigma: 1)
        ..negate()
        ..grayscale()
        ..blackwhite();

      expect(image.width, 10);
      expect(image.height, 7);
      expect(image.toBgra8888().length, 10 * 7 * 4);
    }
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

double _mae(Uint8List a, Uint8List b) {
  int sum = 0;
  for (int i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}

YuvPlane _copyPlaneWithPadding({
  required YuvPlane source,
  required int logicalWidth,
  required int logicalHeight,
  required int dstRowStride,
  required int dstPixelStride,
}) {
  final dst = Uint8List(logicalHeight * dstRowStride);
  for (int y = 0; y < logicalHeight; y++) {
    for (int x = 0; x < logicalWidth; x++) {
      final dstIndex = y * dstRowStride + x * dstPixelStride;
      dst[dstIndex] = source.getPixel(x, y);
    }
  }
  return YuvPlane(logicalHeight, dstRowStride, dstPixelStride, dst);
}

YuvPlane _copyUvInterleavedPlaneWithPadding({
  required YuvPlane source,
  required int logicalRowBytes,
  required int logicalHeight,
  required int dstRowStride,
  required int dstPixelStride,
}) {
  final dst = Uint8List(logicalHeight * dstRowStride);
  for (int y = 0; y < logicalHeight; y++) {
    final srcStart = y * source.rowStride;
    final dstStart = y * dstRowStride;
    dst.setRange(dstStart, dstStart + logicalRowBytes, source.bytes, srcStart);
  }
  return YuvPlane(logicalHeight, dstRowStride, dstPixelStride, dst);
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
