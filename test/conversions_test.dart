import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

const int _w = 512;
const int _h = 512;

final bool _nativeAvailable = _checkNativeAvailable();

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}

Future<Uint8List> _loadPngAsRgba(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
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
  assert(a.length == b.length);
  int sum = 0;
  for (int i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}

bool _allZero(Uint8List bytes) => bytes.every((b) => b == 0);

Uint8List _flipHorizontalBgra(Uint8List src, int width, int height) {
  final out = Uint8List(src.length);
  const bpp = 4;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final sx = width - 1 - x;
      final dstIdx = (y * width + x) * bpp;
      final srcIdx = (y * width + sx) * bpp;
      out.setRange(dstIdx, dstIdx + bpp, src, srcIdx);
    }
  }
  return out;
}

Uint8List _flipVerticalBgra(Uint8List src, int width, int height) {
  final out = Uint8List(src.length);
  const bpp = 4;
  for (int y = 0; y < height; y++) {
    final sy = height - 1 - y;
    for (int x = 0; x < width; x++) {
      final dstIdx = (y * width + x) * bpp;
      final srcIdx = (sy * width + x) * bpp;
      out.setRange(dstIdx, dstIdx + bpp, src, srcIdx);
    }
  }
  return out;
}

Uint8List _cropBgra(Uint8List src, int srcWidth, int left, int top, int cropWidth, int cropHeight) {
  final out = Uint8List(cropWidth * cropHeight * 4);
  const bpp = 4;
  for (int y = 0; y < cropHeight; y++) {
    for (int x = 0; x < cropWidth; x++) {
      final sx = left + x;
      final sy = top + y;
      final dstIdx = (y * cropWidth + x) * bpp;
      final srcIdx = (sy * srcWidth + sx) * bpp;
      out.setRange(dstIdx, dstIdx + bpp, src, srcIdx);
    }
  }
  return out;
}

Uint8List _rotate90CwBgra(Uint8List src, int width, int height) {
  final out = Uint8List(width * height * 4);
  const bpp = 4;
  final dstWidth = height;
  for (int y = 0; y < width; y++) {
    for (int x = 0; x < height; x++) {
      final sx = y;
      final sy = height - 1 - x;
      final dstIdx = (y * dstWidth + x) * bpp;
      final srcIdx = (sy * width + sx) * bpp;
      out.setRange(dstIdx, dstIdx + bpp, src, srcIdx);
    }
  }
  return out;
}

Uint8List _rotate180Bgra(Uint8List src, int width, int height) {
  final out = Uint8List(src.length);
  const bpp = 4;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final sx = width - 1 - x;
      final sy = height - 1 - y;
      final dstIdx = (y * width + x) * bpp;
      final srcIdx = (sy * width + sx) * bpp;
      out.setRange(dstIdx, dstIdx + bpp, src, srcIdx);
    }
  }
  return out;
}

Uint8List _rotate270CwBgra(Uint8List src, int width, int height) {
  final out = Uint8List(width * height * 4);
  const bpp = 4;
  final dstWidth = height;
  for (int y = 0; y < width; y++) {
    for (int x = 0; x < height; x++) {
      final sx = width - 1 - y;
      final sy = x;
      final dstIdx = (y * dstWidth + x) * bpp;
      final srcIdx = (sy * width + sx) * bpp;
      out.setRange(dstIdx, dstIdx + bpp, src, srcIdx);
    }
  }
  return out;
}

void _expectBgraChannelsEqual(Uint8List bgra) {
  for (int i = 0; i < bgra.length; i += 4) {
    expect(bgra[i], bgra[i + 1], reason: 'B != G at pixel ${i ~/ 4}');
    expect(bgra[i + 1], bgra[i + 2], reason: 'G != R at pixel ${i ~/ 4}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List rgba;
  late Uint8List expectedBgra;

  setUpAll(() async {
    try {
      await YuvFfi.ensureInitialized();
    } catch (_) {
      // Tests with native dependency are already guarded by `_nativeAvailable`.
    }
    rgba = await _loadPngAsRgba('test/assets/test_pattern_512.png');
    expect(rgba.length, _w * _h * 4);
    expectedBgra = _rgbaToBgra(rgba);
  });

  test('fromRgba8888 validates input length', () {
    final image = YuvImage.i420(32, 32);
    expect(() => image.fromRgba8888(Uint8List(31 * 32 * 4)), throwsArgumentError);
  });

  test('toBgra8888 repacks padded BGRA rowStride to tight buffer', () {
    const width = 2;
    const height = 2;
    const rowStride = 12; // width*4 + 4 padding bytes
    final padded = Uint8List.fromList([
      // Row 0, two BGRA pixels + padding
      1, 2, 3, 255, 4, 5, 6, 255, 99, 99, 99, 99,
      // Row 1, two BGRA pixels + padding
      7, 8, 9, 255, 10, 11, 12, 255, 88, 88, 88, 88,
    ]);
    final expected = Uint8List.fromList([
      1, 2, 3, 255, 4, 5, 6, 255, // row 0 (tight)
      7, 8, 9, 255, 10, 11, 12, 255, // row 1 (tight)
    ]);

    final image = YuvImage(YuvFileFormat.bgra8888, width, height, yPixelStride: 4, planes: [YuvPlane(height, rowStride, 4, padded)]);

    final out = image.toBgra8888();
    expect(out, orderedEquals(expected));
  });

  test('BGRA fromRgba8888 matches exact channel reorder', () {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);
    final outBgra = image.toBgra8888();
    expect(outBgra, orderedEquals(expectedBgra));
  }, skip: !_nativeAvailable);

  test('I420 round-trip RGBA -> I420 -> BGRA keeps acceptable quality', () {
    final image = YuvImage.i420(_w, _h);
    image.fromRgba8888(rgba);
    final outBgra = image.toBgra8888();
    final err = _mae(outBgra, expectedBgra);
    expect(err, lessThan(18.0));
  }, skip: !_nativeAvailable);

  test('NV21 round-trip RGBA -> NV21 -> BGRA keeps acceptable quality', () {
    final image = YuvImage.nv21(_w, _h);
    image.fromRgba8888(rgba);
    final outBgra = image.toBgra8888();
    final err = _mae(outBgra, expectedBgra);
    expect(err, lessThan(50.0));
  }, skip: !_nativeAvailable);

  test('I420 <-> NV21 conversion preserves image dimensions and can round-trip', () {
    final i420 = YuvImage.i420(_w, _h);
    i420.fromRgba8888(rgba);

    final nv = i420.toYuvNv21();
    expect(identical(nv, i420), isTrue);
    expect(nv.format, YuvPixelFormat.nv12);
    expect(nv.width, _w);
    expect(nv.height, _h);

    final back = nv.toYuvI420();
    expect(identical(back, nv), isTrue);
    expect(back.format, YuvPixelFormat.i420);
    expect(back.width, _w);
    expect(back.height, _h);

    final err = _mae(back.toBgra8888(), expectedBgra);
    expect(err, lessThan(20.0));
  }, skip: !_nativeAvailable);

  test('toYuvBgra8888 returns BGRA image with expected shape', () {
    final nv = YuvImage.nv21(_w, _h);
    nv.fromRgba8888(rgba);
    final bgra = nv.toYuvBgra8888();
    expect(identical(bgra, nv), isTrue);
    expect(bgra.format, YuvPixelFormat.bgra8888);
    expect(bgra.width, _w);
    expect(bgra.height, _h);
    expect(bgra.yPlane.bytes.length, _w * _h * 4);
  }, skip: !_nativeAvailable);

  test('swapNv is reversible after two swaps', () {
    final image = YuvImage.nv21(_w, _h);
    image.fromRgba8888(rgba);
    final original = Uint8List.fromList(image.uPlane.bytes);

    final swapped = image.swapNv();
    expect(identical(swapped, image), isTrue);
    final restored = swapped.swapNv();
    expect(identical(restored, swapped), isTrue);

    expect(restored.uPlane.bytes, orderedEquals(original));
  }, skip: !_nativeAvailable);

  test('swapNv preserves Y and reverses every chroma pair exactly', () {
    const width = 4;
    const height = 4;
    final originalY = Uint8List.fromList([10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]);
    final originalChroma = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final image = YuvImage.nv21(width, height, planes: [YuvPlane(height, width, 1, originalY), YuvPlane(height ~/ 2, width, 2, originalChroma)]);

    final swapped = image.swapNv();

    expect(identical(swapped, image), isTrue);
    expect(swapped.format, YuvPixelFormat.nv12);
    expect(swapped.width, width);
    expect(swapped.height, height);
    expect(swapped.yPlane.bytes, orderedEquals(originalY));
    expect(swapped.uPlane.bytes, orderedEquals(<int>[2, 1, 4, 3, 6, 5, 8, 7]));

    final restored = swapped.swapNv();
    expect(restored.yPlane.bytes, orderedEquals(originalY));
    expect(restored.uPlane.bytes, orderedEquals(originalChroma));
  }, skip: !_nativeAvailable);

  test('swapNv preserves Y after conversion from I420', () {
    const width = 4;
    const height = 4;
    final originalY = Uint8List.fromList([30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45]);
    final image = YuvImage.i420(
      width,
      height,
      planes: [
        YuvPlane(height, width, 1, originalY),
        YuvPlane(height ~/ 2, width ~/ 2, 1, Uint8List.fromList([1, 3, 5, 7])),
        YuvPlane(height ~/ 2, width ~/ 2, 1, Uint8List.fromList([2, 4, 6, 8])),
      ],
    );

    image.swapNv();

    expect(image.format, YuvPixelFormat.nv12);
    expect(image.width, width);
    expect(image.height, height);
    expect(image.yPlane.bytes, orderedEquals(originalY));
    expect(image.uPlane.bytes, orderedEquals(<int>[2, 1, 4, 3, 6, 5, 8, 7]));
  }, skip: !_nativeAvailable);

  test('swapNv preserves padded Y layout after one and two swaps', () {
    const width = 4;
    const height = 4;
    const yRowStride = 6;
    const uvRowStride = 6;
    final originalY = Uint8List.fromList([10, 11, 12, 13, 90, 91, 14, 15, 16, 17, 92, 93, 18, 19, 20, 21, 94, 95, 22, 23, 24, 25, 96, 97]);
    final originalChroma = Uint8List.fromList([1, 2, 3, 4, 80, 81, 5, 6, 7, 8, 82, 83]);
    final image = YuvImage.nv21(
      width,
      height,
      planes: [YuvPlane(height, yRowStride, 1, originalY), YuvPlane(height ~/ 2, uvRowStride, 2, originalChroma)],
    );
    final sourceYPlane = image.yPlane;
    final sourceChromaPlane = image.uPlane;

    image.swapNv();

    expect(identical(image.yPlane, sourceYPlane), isFalse);
    expect(identical(image.yPlane.bytes, sourceYPlane.bytes), isFalse);
    expect(identical(image.uPlane, sourceChromaPlane), isFalse);
    expect(identical(image.uPlane.bytes, sourceChromaPlane.bytes), isFalse);
    expect(image.yPlane.rowStride, yRowStride);
    expect(image.yPlane.bytes, orderedEquals(originalY));
    expect(image.uPlane.rowStride, uvRowStride);
    expect(image.uPlane.bytes.sublist(0, 4), orderedEquals(<int>[2, 1, 4, 3]));
    expect(image.uPlane.bytes.sublist(uvRowStride, uvRowStride + 4), orderedEquals(<int>[6, 5, 8, 7]));

    image.swapNv();

    expect(image.yPlane.bytes, orderedEquals(originalY));
    expect(image.uPlane.bytes.sublist(0, 4), orderedEquals(<int>[1, 2, 3, 4]));
    expect(image.uPlane.bytes.sublist(uvRowStride, uvRowStride + 4), orderedEquals(<int>[5, 6, 7, 8]));
  }, skip: !_nativeAvailable);

  test('flipHorizontally on BGRA is exact', () {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);
    image.flipHorizontally();

    final expected = _flipHorizontalBgra(expectedBgra, _w, _h);
    expect(image.toBgra8888(), orderedEquals(expected));
  }, skip: !_nativeAvailable);

  test('flipVertically on BGRA is exact', () {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);
    image.flipVertically();

    final expected = _flipVerticalBgra(expectedBgra, _w, _h);
    expect(image.toBgra8888(), orderedEquals(expected));
  }, skip: !_nativeAvailable);

  test('crop on BGRA is exact', () {
    const left = 64;
    const top = 96;
    const cw = 256;
    const ch = 320;

    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);
    image.crop(ui.Rect.fromLTWH(left.toDouble(), top.toDouble(), cw.toDouble(), ch.toDouble()));

    final expected = _cropBgra(expectedBgra, _w, left, top, cw, ch);
    expect(image.width, cw);
    expect(image.height, ch);
    expect(image.toBgra8888(), orderedEquals(expected));
  }, skip: !_nativeAvailable);

  test('crop clamps out-of-bounds rect and keeps no-op for empty crop', () {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);

    image.crop(const ui.Rect.fromLTWH(-50.3, -10.5, 9999.0, 9999.0));
    expect(image.width, _w);
    expect(image.height, _h);
    expect(image.toBgra8888(), orderedEquals(expectedBgra));

    final before = image.toBgra8888();
    image.crop(const ui.Rect.fromLTWH(100.0, 100.0, -20.0, 10.0));
    expect(image.width, _w);
    expect(image.height, _h);
    expect(image.toBgra8888(), orderedEquals(before));
  }, skip: !_nativeAvailable);

  test('rotate 90 on BGRA is exact', () {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);
    image.rotate(YuvImageRotation.rotation90);

    final expected = _rotate90CwBgra(expectedBgra, _w, _h);
    expect(image.width, _h);
    expect(image.height, _w);
    expect(image.toBgra8888(), orderedEquals(expected));
  }, skip: !_nativeAvailable);

  test('rotate 180 on BGRA is exact', () {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);
    image.rotate(YuvImageRotation.rotation180);

    final expected = _rotate180Bgra(expectedBgra, _w, _h);
    expect(image.width, _w);
    expect(image.height, _h);
    expect(image.toBgra8888(), orderedEquals(expected));
  }, skip: !_nativeAvailable);

  test('rotate 270 on BGRA is exact', () {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);
    image.rotate(YuvImageRotation.rotation270);

    final expected = _rotate270CwBgra(expectedBgra, _w, _h);
    expect(image.width, _h);
    expect(image.height, _w);
    expect(image.toBgra8888(), orderedEquals(expected));
  }, skip: !_nativeAvailable);

  test('grayscale on BGRA makes RGB channels equal and keeps alpha', () {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);
    final before = Uint8List.fromList(image.toBgra8888());

    image.grayscale();
    final after = image.toBgra8888();

    _expectBgraChannelsEqual(after);
    for (int i = 3; i < after.length; i += 4) {
      expect(after[i], before[i], reason: 'Alpha changed at pixel ${i ~/ 4}');
    }
  }, skip: !_nativeAvailable);

  test('blackwhite on BGRA produces binary grayscale and keeps alpha', () {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);
    final before = Uint8List.fromList(image.toBgra8888());

    image.blackwhite();
    final after = image.toBgra8888();

    _expectBgraChannelsEqual(after);
    for (int i = 0; i < after.length; i += 4) {
      expect(after[i] == 0 || after[i] == 255, isTrue);
    }
    for (int i = 3; i < after.length; i += 4) {
      expect(after[i], before[i], reason: 'Alpha changed at pixel ${i ~/ 4}');
    }
  }, skip: !_nativeAvailable);

  test('negate on BGRA inverts RGB and keeps alpha', () {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);
    final before = Uint8List.fromList(image.toBgra8888());

    image.negate();
    final after = image.toBgra8888();

    for (int i = 0; i < after.length; i += 4) {
      expect(after[i], 255 - before[i], reason: 'B mismatch at pixel ${i ~/ 4}');
      expect(after[i + 1], 255 - before[i + 1], reason: 'G mismatch at pixel ${i ~/ 4}');
      expect(after[i + 2], 255 - before[i + 2], reason: 'R mismatch at pixel ${i ~/ 4}');
      expect(after[i + 3], before[i + 3], reason: 'A mismatch at pixel ${i ~/ 4}');
    }
  }, skip: !_nativeAvailable);

  test('copy preserves data and blank copy zeros all planes', () {
    final image = YuvImage.i420(_w, _h);
    image.fromRgba8888(rgba);

    final copied = image.copy();
    expect(copied.getBytes(), orderedEquals(image.getBytes()));

    copied.yPlane.bytes[0] = copied.yPlane.bytes[0] ^ 0xFF;
    expect(copied.yPlane.bytes[0], isNot(image.yPlane.bytes[0]));

    final blank = image.copy(blank: true);
    for (final p in blank.planes) {
      expect(_allZero(p.bytes), isTrue);
    }
  }, skip: !_nativeAvailable);

  test('save/load round-trip preserves i420 image bytes', () async {
    final image = YuvImage.i420(_w, _h);
    image.fromRgba8888(rgba);

    final chunks = <List<int>>[];
    final stream = StreamController<List<int>>();
    final sub = stream.stream.listen(chunks.add);
    await image.save(stream.sink);
    await stream.close();
    await sub.cancel();

    final loaded = YuvImage.i420(1, 1);
    await loaded.load(Stream<List<int>>.fromIterable(chunks));

    expect(loaded.format, image.format);
    expect(loaded.width, image.width);
    expect(loaded.height, image.height);
    expect(loaded.getBytes(), orderedEquals(image.getBytes()));
  }, skip: !_nativeAvailable);

  test('toImage returns image with expected dimensions', () async {
    final image = YuvImage.bgra(_w, _h);
    image.fromRgba8888(rgba);

    final uiImage = await image.toImage();
    expect(uiImage.width, _w);
    expect(uiImage.height, _h);
  }, skip: !_nativeAvailable);

  test('blur operations smoke test across formats', () {
    final rect = ui.Rect.fromLTWH(32, 32, 256, 256);

    final i420 = YuvImage.i420(_w, _h)..fromRgba8888(rgba);
    i420.gaussianBlur(radius: 3, sigma: 2);
    i420.boxBlur(radius: 5, rect: rect);
    i420.meanBlur(radius: 5, rect: rect);
    expect(i420.width, _w);
    expect(i420.height, _h);
    expect(i420.toBgra8888().length, _w * _h * 4);

    final nv21 = YuvImage.nv21(_w, _h)..fromRgba8888(rgba);
    nv21.gaussianBlur(radius: 3, sigma: 2);
    nv21.boxBlur(radius: 5, rect: rect);
    nv21.meanBlur(radius: 5, rect: rect);
    expect(nv21.width, _w);
    expect(nv21.height, _h);
    expect(nv21.toBgra8888().length, _w * _h * 4);

    final bgra = YuvImage.bgra(_w, _h)..fromRgba8888(rgba);
    bgra.gaussianBlur(radius: 3, sigma: 2);
    bgra.boxBlur(radius: 5, rect: rect);
    bgra.meanBlur(radius: 5, rect: rect);
    expect(bgra.width, _w);
    expect(bgra.height, _h);
    expect(bgra.toBgra8888().length, _w * _h * 4);
  }, skip: !_nativeAvailable);

  // Like the getBytes group below, these cases only allocate planes in Dart and
  // must run without a native library.
  group('padded BGRA constructor contract', () {
    /// Builds a plane whose buffer exactly matches its declared geometry.
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

    test('a tight plane is still kept tight', () {
      final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 8)]);
      expect(image.yPlane.rowStride, 8);
      expect(image.yPlane.bytes.length, 16);
    });

    test('the constructor deep-copies instead of aliasing the caller plane', () {
      final source = plane(2, 16);
      source.bytes[0] = 42;
      final image = YuvImage.bgra(2, 2, planes: <YuvPlane>[source]);

      source.bytes[0] = 200;
      expect(image.yPlane.bytes[0], 42, reason: 'the image must not alias the caller buffer');
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
      expect(blank.yPlane.rowStride, 16, reason: 'a blank copy must not silently drop the padding');
      expect(blank.yPlane.bytes.length, 32);
      expect(blank.yPlane.bytes.every((b) => b == 0), isTrue);
    });

    test('an invalid padded layout throws ArgumentError, not a RangeError', () {
      // A row that cannot hold width * 4 bytes is genuinely invalid, and both
      // entry points must reject it through the shared validator.
      expect(() => YuvImage.bgra(2, 2, planes: <YuvPlane>[plane(2, 4)]), throwsArgumentError);
      expect(() => YuvImage(YuvFileFormat.bgra8888, 2, 2, yPixelStride: 4, planes: <YuvPlane>[plane(2, 4)]), throwsArgumentError);
    });
  });

  // These cases only allocate planes in Dart, so they must run without a native
  // library. Guarding them with `skip: !_nativeAvailable` would let the F-003
  // regression pass unnoticed on a machine with no built binary.
  group('getBytes contract', () {
    const sizes = <({int w, int h})>[(w: 1, h: 1), (w: 3, h: 3), (w: 127, h: 255), (w: 512, h: 512)];

    for (final size in sizes) {
      test('returns exactly the summed plane length for ${size.w}x${size.h}', () {
        for (final image in _imagesForEachFormat(size.w, size.h)) {
          final expectedLength = image.planes.fold<int>(0, (sum, plane) => sum + plane.bytes.length);

          expect(image.getBytes(), hasLength(expectedLength), reason: '${image.format.name} ${size.w}x${size.h} must not carry an alignment tail');
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

      // Mutating the returned buffer must not reach back into the planes.
      snapshot[0] = snapshot[0] ^ 0xFF;
      expect(image.yPlane.bytes[0], planeByteBefore);

      // Mutating a plane must not retroactively change an earlier result.
      final snapshotByteBefore = snapshot[1];
      image.yPlane.bytes[1] = image.yPlane.bytes[1] ^ 0xFF;
      expect(snapshot[1], snapshotByteBefore);
    });

    test('F-003 diagnostic case: i420 3x3 has no alignment tail', () {
      final image = YuvImage.i420(3, 3);
      final expectedLength = image.planes.fold<int>(0, (sum, plane) => sum + plane.bytes.length);

      // Y: 3x3 = 9 bytes. Chroma: ceil(3/2) x ceil(3/2) = 2x2, one byte per
      // sample for I420's planar (not interleaved) U and V, 4 bytes each.
      expect(expectedLength, 17);
      expect(image.getBytes(), hasLength(expectedLength));
    });
  });
}

/// Builds one image per public format, so a contract case covers BGRA, I420 and
/// the legacy `nv21` name without repeating itself.
///
/// The legacy `nv21` name keeps its current NV12-like UV byte order; these
/// cases only concatenate planes and never reinterpret chroma.
List<YuvImage> _imagesForEachFormat(int w, int h) => <YuvImage>[YuvImage.bgra(w, h), YuvImage.i420(w, h), YuvImage.nv21(w, h)];

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

/// Expected value built by direct concatenation rather than by the other
/// backend, so a shared defect cannot hide in both sides of the comparison.
Uint8List _concatPlanesDirectly(YuvImage image) {
  final out = <int>[];
  for (final plane in image.planes) {
    out.addAll(plane.bytes);
  }
  return Uint8List.fromList(out);
}
