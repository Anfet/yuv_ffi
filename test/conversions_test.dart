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
    openYuvLibrary();
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

Uint8List _cropBgra(
  Uint8List src,
  int srcWidth,
  int left,
  int top,
  int cropWidth,
  int cropHeight,
) {
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
    rgba = await _loadPngAsRgba('test/assets/test_pattern_512.png');
    expect(rgba.length, _w * _h * 4);
    expectedBgra = _rgbaToBgra(rgba);
  });

  test('fromRgba8888 validates input length', () {
    final image = YuvImage.i420(32, 32);
    expect(
      () => image.fromRgba8888(Uint8List(31 * 32 * 4)),
      throwsArgumentError,
    );
  });

  test(
    'BGRA fromRgba8888 matches exact channel reorder',
    () {
      final image = YuvImage.bgra(_w, _h);
      image.fromRgba8888(rgba);
      final outBgra = image.toBgra8888();
      expect(outBgra, orderedEquals(expectedBgra));
    },
    skip: !_nativeAvailable,
  );

  test(
    'I420 round-trip RGBA -> I420 -> BGRA keeps acceptable quality',
    () {
      final image = YuvImage.i420(_w, _h);
      image.fromRgba8888(rgba);
      final outBgra = image.toBgra8888();
      final err = _mae(outBgra, expectedBgra);
      expect(err, lessThan(18.0));
    },
    skip: !_nativeAvailable,
  );

  test(
    'NV21 round-trip RGBA -> NV21 -> BGRA keeps acceptable quality',
    () {
      final image = YuvImage.nv21(_w, _h);
      image.fromRgba8888(rgba);
      final outBgra = image.toBgra8888();
      final err = _mae(outBgra, expectedBgra);
      expect(err, lessThan(50.0));
    },
    skip: !_nativeAvailable,
  );

  test(
    'I420 <-> NV21 conversion preserves image dimensions and can round-trip',
    () {
      final i420 = YuvImage.i420(_w, _h);
      i420.fromRgba8888(rgba);

      final nv = i420.toYuvNv21();
      expect(nv.format, YuvFileFormat.nv21);
      expect(nv.width, _w);
      expect(nv.height, _h);

      final back = nv.toYuvI420();
      expect(back.format, YuvFileFormat.i420);
      expect(back.width, _w);
      expect(back.height, _h);

      final err = _mae(back.toBgra8888(), expectedBgra);
      expect(err, lessThan(20.0));
    },
    skip: !_nativeAvailable,
  );

  test(
    'toYuvBgra8888 returns BGRA image with expected shape',
    () {
      final nv = YuvImage.nv21(_w, _h);
      nv.fromRgba8888(rgba);
      final bgra = nv.toYuvBgra8888();
      expect(bgra.format, YuvFileFormat.bgra8888);
      expect(bgra.width, _w);
      expect(bgra.height, _h);
      expect(bgra.yPlane.bytes.length, _w * _h * 4);
    },
    skip: !_nativeAvailable,
  );

  test(
    'swapNv is reversible after two swaps',
    () {
      final image = YuvImage.nv21(_w, _h);
      image.fromRgba8888(rgba);
      final original = Uint8List.fromList(image.uPlane.bytes);

      final swapped = image.swapNv();
      final restored = swapped.swapNv();

      expect(restored.uPlane.bytes, orderedEquals(original));
    },
    skip: !_nativeAvailable,
  );

  test(
    'flipHorizontally on BGRA is exact',
    () {
      final image = YuvImage.bgra(_w, _h);
      image.fromRgba8888(rgba);
      image.flipHorizontally();

      final expected = _flipHorizontalBgra(expectedBgra, _w, _h);
      expect(image.toBgra8888(), orderedEquals(expected));
    },
    skip: !_nativeAvailable,
  );

  test(
    'flipVertically on BGRA is exact',
    () {
      final image = YuvImage.bgra(_w, _h);
      image.fromRgba8888(rgba);
      image.flipVertically();

      final expected = _flipVerticalBgra(expectedBgra, _w, _h);
      expect(image.toBgra8888(), orderedEquals(expected));
    },
    skip: !_nativeAvailable,
  );

  test(
    'crop on BGRA is exact',
    () {
      const left = 64;
      const top = 96;
      const cw = 256;
      const ch = 320;

      final image = YuvImage.bgra(_w, _h);
      image.fromRgba8888(rgba);
      image.crop(ui.Rect.fromLTWH(
          left.toDouble(), top.toDouble(), cw.toDouble(), ch.toDouble()));

      final expected = _cropBgra(expectedBgra, _w, left, top, cw, ch);
      expect(image.width, cw);
      expect(image.height, ch);
      expect(image.toBgra8888(), orderedEquals(expected));
    },
    skip: !_nativeAvailable,
  );

  test(
    'rotate 90 on BGRA is exact',
    () {
      final image = YuvImage.bgra(_w, _h);
      image.fromRgba8888(rgba);
      image.rotate(YuvImageRotation.rotation90);

      final expected = _rotate90CwBgra(expectedBgra, _w, _h);
      expect(image.width, _h);
      expect(image.height, _w);
      expect(image.toBgra8888(), orderedEquals(expected));
    },
    skip: !_nativeAvailable,
  );

  test(
    'rotate 180 on BGRA is exact',
    () {
      final image = YuvImage.bgra(_w, _h);
      image.fromRgba8888(rgba);
      image.rotate(YuvImageRotation.rotation180);

      final expected = _rotate180Bgra(expectedBgra, _w, _h);
      expect(image.width, _w);
      expect(image.height, _h);
      expect(image.toBgra8888(), orderedEquals(expected));
    },
    skip: !_nativeAvailable,
  );

  test(
    'rotate 270 on BGRA is exact',
    () {
      final image = YuvImage.bgra(_w, _h);
      image.fromRgba8888(rgba);
      image.rotate(YuvImageRotation.rotation270);

      final expected = _rotate270CwBgra(expectedBgra, _w, _h);
      expect(image.width, _h);
      expect(image.height, _w);
      expect(image.toBgra8888(), orderedEquals(expected));
    },
    skip: !_nativeAvailable,
  );

  test(
    'grayscale on BGRA makes RGB channels equal and keeps alpha',
    () {
      final image = YuvImage.bgra(_w, _h);
      image.fromRgba8888(rgba);
      final before = Uint8List.fromList(image.toBgra8888());

      image.grayscale();
      final after = image.toBgra8888();

      _expectBgraChannelsEqual(after);
      for (int i = 3; i < after.length; i += 4) {
        expect(after[i], before[i], reason: 'Alpha changed at pixel ${i ~/ 4}');
      }
    },
    skip: !_nativeAvailable,
  );

  test(
    'blackwhite on BGRA produces binary grayscale and keeps alpha',
    () {
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
    },
    skip: !_nativeAvailable,
  );

  test(
    'negate on BGRA inverts RGB and keeps alpha',
    () {
      final image = YuvImage.bgra(_w, _h);
      image.fromRgba8888(rgba);
      final before = Uint8List.fromList(image.toBgra8888());

      image.negate();
      final after = image.toBgra8888();

      for (int i = 0; i < after.length; i += 4) {
        expect(after[i], 255 - before[i],
            reason: 'B mismatch at pixel ${i ~/ 4}');
        expect(after[i + 1], 255 - before[i + 1],
            reason: 'G mismatch at pixel ${i ~/ 4}');
        expect(after[i + 2], 255 - before[i + 2],
            reason: 'R mismatch at pixel ${i ~/ 4}');
        expect(after[i + 3], before[i + 3],
            reason: 'A mismatch at pixel ${i ~/ 4}');
      }
    },
    skip: !_nativeAvailable,
  );

  test(
    'copy preserves data and blank copy zeros all planes',
    () {
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
    },
    skip: !_nativeAvailable,
  );

  test(
    'save/load round-trip preserves i420 image bytes',
    () async {
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
    },
    skip: !_nativeAvailable,
  );

  test(
    'toImage returns image with expected dimensions',
    () async {
      final image = YuvImage.bgra(_w, _h);
      image.fromRgba8888(rgba);

      final uiImage = await image.toImage();
      expect(uiImage.width, _w);
      expect(uiImage.height, _h);
    },
    skip: !_nativeAvailable,
  );

  test(
    'blur operations smoke test across formats',
    () {
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
    },
    skip: !_nativeAvailable,
  );
}
