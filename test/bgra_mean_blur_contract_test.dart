import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies YUV-42: the BGRA mean blur is deterministic, leaves everything
/// outside the ROI untouched, keeps alpha exact, and averages over a
/// clamp-to-edge kernel rather than a truncated window.
///
/// The historical defect wrote only inside the ROI but copied a whole
/// `malloc`'d scratch buffer back, so pixels outside the ROI came from
/// uninitialized heap and differed between runs.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  /// Builds a tight BGRA image with a deterministic, non-uniform pattern.
  YuvImage patternImage(int width, int height) {
    final bytes = Uint8List(width * height * 4);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        bytes[i + 0] = (x * 7 + y * 3) & 0xFF;
        bytes[i + 1] = (x * 11 + y * 5) & 0xFF;
        bytes[i + 2] = (x * 13 + y * 17) & 0xFF;
        // Deliberately non-uniform: a constant alpha would survive averaging
        // as well as copying, so it could not tell the two apart.
        bytes[i + 3] = (x * 19 + y * 23) & 0xFF;
      }
    }
    return YuvImage(YuvFileFormat.bgra8888, width, height, planes: [YuvPlane(height, width * 4, 4, bytes)]);
  }

  test('pixels outside the ROI keep their original bytes', () {
    if (!nativeAvailable) {
      markTestSkipped('native library is not available on this host');
      return;
    }
    final source = patternImage(32, 32);
    final original = Uint8List.fromList(source.yPlane.bytes);

    source.meanBlur(radius: 3, rect: const ui.Rect.fromLTRB(8, 8, 16, 16));

    final blurred = source.yPlane.bytes;
    for (int y = 0; y < 32; y++) {
      for (int x = 0; x < 32; x++) {
        final inRoi = x >= 8 && x < 16 && y >= 8 && y < 16;
        if (inRoi) continue;
        final i = (y * 32 + x) * 4;
        expect(
          blurred.sublist(i, i + 4),
          orderedEquals(original.sublist(i, i + 4)),
          reason: 'pixel ($x, $y) lies outside the ROI and must not change',
        );
      }
    }
  });

  test('repeated runs on identical input produce identical output', () {
    if (!nativeAvailable) {
      markTestSkipped('native library is not available on this host');
      return;
    }
    final first = patternImage(24, 24)..meanBlur(radius: 4, rect: const ui.Rect.fromLTRB(4, 4, 12, 12));
    final second = patternImage(24, 24)..meanBlur(radius: 4, rect: const ui.Rect.fromLTRB(4, 4, 12, 12));

    expect(first.yPlane.bytes, orderedEquals(second.yPlane.bytes));
  });

  test('alpha is preserved exactly, byte for byte', () {
    if (!nativeAvailable) {
      markTestSkipped('native library is not available on this host');
      return;
    }
    // The source alpha varies per pixel, so averaging it would visibly differ
    // from copying it. A uniform-alpha fixture would pass either way, which is
    // how an averaged alpha channel previously went unnoticed.
    final source = patternImage(16, 16);
    final original = Uint8List.fromList(source.yPlane.bytes);

    source.meanBlur(radius: 2);

    for (int i = 3; i < source.yPlane.bytes.length; i += 4) {
      expect(source.yPlane.bytes[i], original[i], reason: 'alpha at byte $i must be untouched');
    }
    // Guards the fixture itself: if alpha were constant the loop above would
    // hold even for an averaged alpha channel.
    final alphas = <int>{for (int i = 3; i < original.length; i += 4) original[i]};
    expect(alphas.length, greaterThan(1), reason: 'fixture must vary alpha');
  });

  test('borders average over a replicated kernel, not a truncated window', () {
    if (!nativeAvailable) {
      markTestSkipped('native library is not available on this host');
      return;
    }
    // Vertical split: left half 0, right half 200. At the right edge a
    // replicated kernel keeps averaging 200 (the edge column is duplicated),
    // while a truncated window would pull the mean toward the darker side.
    const w = 16, h = 8, r = 3;
    final bytes = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final v = x < w ~/ 2 ? 0 : 200;
        bytes[i] = v;
        bytes[i + 1] = v;
        bytes[i + 2] = v;
        bytes[i + 3] = 0xFF;
      }
    }
    final image = YuvImage(YuvFileFormat.bgra8888, w, h, planes: [YuvPlane(h, w * 4, 4, bytes)])..meanBlur(radius: r);

    // The last column lies more than `radius` away from the split, so every
    // kernel sample — real or replicated — is 200.
    for (int y = 0; y < h; y++) {
      expect(image.yPlane.bytes[(y * w + (w - 1)) * 4], 200, reason: 'row $y, last column');
    }
  });

  test('a uniform image is unchanged, including at the clamped borders', () {
    if (!nativeAvailable) {
      markTestSkipped('native library is not available on this host');
      return;
    }
    // Averaging a constant field returns the same constant only when the
    // border kernel replicates the edge; a truncated window would still
    // average to the same value here, so this guards the weighting arithmetic
    // (division by the full kernel area) rather than the window itself.
    final bytes = Uint8List(12 * 12 * 4)..fillRange(0, 12 * 12 * 4, 0x40);
    final image = YuvImage(YuvFileFormat.bgra8888, 12, 12, planes: [YuvPlane(12, 12 * 4, 4, bytes)])..meanBlur(radius: 5);

    expect(image.yPlane.bytes.every((b) => b == 0x40), isTrue);
  });

  test('an empty ROI is a no-op', () {
    if (!nativeAvailable) {
      markTestSkipped('native library is not available on this host');
      return;
    }
    final image = patternImage(16, 16);
    final original = Uint8List.fromList(image.yPlane.bytes);

    image.meanBlur(radius: 3, rect: const ui.Rect.fromLTRB(8, 8, 8, 8));

    expect(image.yPlane.bytes, orderedEquals(original));
  });

  test('a large uniform frame does not overflow the SAT accumulator', () {
    if (!nativeAvailable) {
      markTestSkipped('native library is not available on this host');
      return;
    }
    // Regression guard for the P1 review finding on 2026-09-20: the SAT
    // accumulators used to be int32_t, and a single-channel SAT cell at the
    // bottom-right corner sums every sample in the plane. An all-white frame
    // of 3000x2900 pixels (255 per sample, one channel) sums to
    // 2,218,500,000, already past INT32_MAX (2,147,483,647) — smaller than a
    // real 4K frame (4096x2160 sums to 2,256,076,800) but large enough to
    // exercise the same overflow deterministically without allocating a full
    // 4K buffer.
    //
    // A 32-bit accumulator would wrap into a negative or corrupted sum here,
    // producing a blurred value far from the uniform 255 every pixel of a
    // flat white frame must blur to. int64_t keeps the same worst case in
    // range through 16K frames.
    const width = 3000;
    const height = 2900;
    final bytes = Uint8List(width * height * 4)..fillRange(0, width * height * 4, 0xFF);
    final image = YuvImage(YuvFileFormat.bgra8888, width, height, planes: [YuvPlane(height, width * 4, 4, bytes)]);

    image.meanBlur(radius: 4);

    // Every channel of a flat white frame must still blur to 255: a wrapped
    // or corrupted SAT sum would produce a wrong, non-255 average instead.
    for (int i = 0; i < image.yPlane.bytes.length; i += 4) {
      expect(image.yPlane.bytes[i], 0xFF, reason: 'blue at pixel ${i ~/ 4}');
      expect(image.yPlane.bytes[i + 1], 0xFF, reason: 'green at pixel ${i ~/ 4}');
      expect(image.yPlane.bytes[i + 2], 0xFF, reason: 'red at pixel ${i ~/ 4}');
      expect(image.yPlane.bytes[i + 3], 0xFF, reason: 'alpha at pixel ${i ~/ 4}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an invalid radius is rejected before reaching native code', () {
    // Regression guard for the general P1 review finding on 2026-09-20:
    // boxBlur/meanBlur/gaussianBlur passed any radius straight to C without
    // validation. A negative radius inverts the SAT rectangle bounds
    // (x1 > x2, y1 > y2) and reads/writes out of bounds; this does not need
    // nativeAvailable, since validation happens in Dart before any native
    // call or allocation.
    final image = patternImage(8, 8);
    expect(() => image.meanBlur(radius: -1), throwsArgumentError);
    expect(() => image.boxBlur(radius: -1), throwsArgumentError);
    expect(() => image.gaussianBlur(radius: -1), throwsArgumentError);
    expect(() => image.meanBlur(radius: 257), throwsArgumentError);
    expect(() => image.boxBlur(radius: 257), throwsArgumentError);
    expect(() => image.gaussianBlur(radius: 257), throwsArgumentError);
  });
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
