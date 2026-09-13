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

  test('fromRgba8888 preserves padded destination bytes', () {
    const w = 3;
    const h = 5;
    final rgba = _buildRgbaPattern(w, h);
    final y = Uint8List(h * (w * 2 + 3))..fillRange(0, h * (w * 2 + 3), 0xA5);
    final uvW = (w + 1) ~/ 2;
    final uvH = (h + 1) ~/ 2;
    final u = Uint8List(uvH * (uvW * 2 + 2))..fillRange(0, uvH * (uvW * 2 + 2), 0xA5);
    final v = Uint8List.fromList(u);
    final image = YuvImage.i420(
      w,
      h,
      planes: [
        YuvPlane(h, w * 2 + 3, 2, y),
        YuvPlane(uvH, uvW * 2 + 2, 2, u),
        YuvPlane(uvH, uvW * 2 + 2, 2, v),
      ],
    )..fromRgba8888(rgba);

    _expectPadding(image.yPlane, logicalWidth: w, sampleBytes: 1);
    _expectPadding(image.uPlane, logicalWidth: uvW, sampleBytes: 1);
    _expectPadding(image.vPlane, logicalWidth: uvW, sampleBytes: 1);
  });

  test('swapNv preserves padded layout and swaps only UV pairs', () {
    const w = 5;
    const h = 3;
    const yStride = 9;
    const uvStride = 9;
    final y = Uint8List(h * yStride)..fillRange(0, h * yStride, 0xA5);
    final uv = Uint8List(((h + 1) ~/ 2) * uvStride)..fillRange(0, ((h + 1) ~/ 2) * uvStride, 0xA5);
    for (int row = 0; row < (h + 1) ~/ 2; row++) {
      for (int column = 0; column < (w + 1) ~/ 2; column++) {
        final offset = row * uvStride + column * 2;
        uv[offset] = 40 + column;
        uv[offset + 1] = 180 + row;
      }
    }
    final image = YuvImage.nv21(
      w,
      h,
      planes: [YuvPlane(h, yStride, 1, y), YuvPlane((h + 1) ~/ 2, uvStride, 2, uv)],
    )..swapNv();

    expect(image.yPlane.rowStride, yStride);
    expect(image.uPlane.rowStride, uvStride);
    for (int row = 0; row < (h + 1) ~/ 2; row++) {
      for (int column = 0; column < (w + 1) ~/ 2; column++) {
        final offset = row * uvStride + column * 2;
        expect(image.uPlane.bytes[offset], 180 + row);
        expect(image.uPlane.bytes[offset + 1], 40 + column);
      }
    }
    _expectPadding(image.yPlane, logicalWidth: w, sampleBytes: 1);
    _expectPadding(image.uPlane, logicalWidth: (w + 1) ~/ 2, sampleBytes: 2, expected: 0);
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

  group('padded BGRA constructor contract', () {
    YuvPlane plane(int height, int rowStride, [int pixelStride = 4]) => YuvPlane(height, rowStride, pixelStride, Uint8List(height * rowStride));

    test('F-004 diagnostic case: a valid padded plane is accepted', () {
      expect(() => YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 16)]), returnsNormally);
    });

    test('specialized and generic constructors agree on a padded plane', () {
      final specialized = YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 16)]);
      final generic = YuvImage(YuvFileFormat.bgra8888, 2, 2, yPixelStride: 4, planes: <YuvPlane>[plane(2, 16)]);

      for (final image in <YuvImage>[specialized, generic]) {
        expect(image.yPlane.rowStride, 16);
        expect(image.yPlane.pixelStride, 4);
        expect(image.yPlane.bytes.length, 32);
      }
    });

    test('copy keeps padded metadata and blank copy zeros the whole allocation', () {
      final source = plane(2, 16);
      for (int i = 0; i < source.bytes.length; i++) {
        source.bytes[i] = i + 1;
      }
      final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[source]);

      final copied = image.copy();
      expect(copied.yPlane.rowStride, 16);
      expect(copied.yPlane.bytes, orderedEquals(image.yPlane.bytes));

      final blank = image.copy(blank: true);
      expect(blank.yPlane.rowStride, 16);
      expect(blank.yPlane.bytes.every((b) => b == 0), isTrue);
    });

    test('an invalid padded layout throws ArgumentError, not a RangeError', () {
      expect(() => YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 4)]), throwsArgumentError);
      expect(
        () => YuvImage(YuvFileFormat.bgra8888, 2, 2, yPixelStride: 4, planes: <YuvPlane>[plane(2, 4)]),
        throwsArgumentError,
      );
    });
  });

  group('getBytes contract', () {
    const sizes = <({int w, int h})>[
      (w: 1, h: 1),
      (w: 3, h: 3),
      (w: 127, h: 255),
      (w: 512, h: 512),
    ];

    for (final size in sizes) {
      test('returns exactly the summed plane length for ${size.w}x${size.h}', () {
        for (final image in _imagesForEachFormat(size.w, size.h)) {
          final expectedLength = image.planes.fold<int>(0, (sum, plane) => sum + plane.bytes.length);

          expect(
            image.getBytes(),
            hasLength(expectedLength),
            reason: '${image.format.name} ${size.w}x${size.h} must not carry an alignment tail',
          );
        }
      });

      test('equals a direct concatenation for ${size.w}x${size.h}', () {
        for (final image in _imagesForEachFormat(size.w, size.h)) {
          _fillPlanesWithPattern(image);

          expect(
            image.getBytes(),
            orderedEquals(_concatPlanesDirectly(image)),
            reason: '${image.format.name} ${size.w}x${size.h} must concatenate planes in format order',
          );
        }
      });
    }

    test('returns an independent copy in both directions', () {
      final image = YuvImage.i420(4, 4);
      _fillPlanesWithPattern(image);

      final snapshot = image.getBytes();
      final planeByteBefore = image.yPlane.bytes[0];

      snapshot[0] = snapshot[0] ^ 0xFF;
      expect(image.yPlane.bytes[0], planeByteBefore);

      final snapshotByteBefore = snapshot[1];
      image.yPlane.bytes[1] = image.yPlane.bytes[1] ^ 0xFF;
      expect(snapshot[1], snapshotByteBefore);
    });

    test('F-003 diagnostic case: i420 3x3 has no alignment tail', () {
      final image = YuvImage.i420(3, 3);
      final expectedLength = image.planes.fold<int>(0, (sum, plane) => sum + plane.bytes.length);

      expect(expectedLength, 25);
      expect(image.getBytes(), hasLength(expectedLength));
    });
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

void _expectPadding(
  YuvPlane plane, {
  required int logicalWidth,
  required int sampleBytes,
  int expected = 0xA5,
}) {
  for (int row = 0; row < plane.height; row++) {
    final logicalOffsets = <int>{};
    for (int column = 0; column < logicalWidth; column++) {
      final start = column * plane.pixelStride;
      for (int byte = 0; byte < sampleBytes; byte++) {
        logicalOffsets.add(start + byte);
      }
    }
    for (int offset = 0; offset < plane.rowStride; offset++) {
      if (!logicalOffsets.contains(offset)) {
        expect(plane.bytes[row * plane.rowStride + offset], expected);
      }
    }
  }
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

/// Builds one image per public format, so a contract case covers BGRA, I420 and
/// the legacy `nv21` name without repeating itself.
///
/// The legacy `nv21` name keeps its current NV12-like UV byte order; these
/// cases only concatenate planes and never reinterpret chroma.
List<YuvImage> _imagesForEachFormat(int w, int h) => <YuvImage>[
      YuvImage.bgra(w, h),
      YuvImage.i420(w, h),
      YuvImage.nv21(w, h),
    ];

/// Writes a per-plane pattern so a misordered or truncated concatenation cannot
/// coincidentally match an all-zero buffer.
void _fillPlanesWithPattern(YuvImage image) {
  for (int i = 0; i < image.planes.length; i++) {
    final bytes = image.planes[i].bytes;
    for (int j = 0; j < bytes.length; j++) {
      bytes[j] = ((i + 1) * 37 + j) & 0xFF;
    }
  }
}

/// Expected value built by direct concatenation rather than by the native
/// backend, so a shared defect cannot hide in both sides of the comparison.
Uint8List _concatPlanesDirectly(YuvImage image) {
  final out = <int>[];
  for (final plane in image.planes) {
    out.addAll(plane.bytes);
  }
  return Uint8List.fromList(out);
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
