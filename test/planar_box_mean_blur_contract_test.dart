import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies YUV-43: I420 and NV21 box/mean blur are deterministic, leave
/// everything outside the ROI untouched, and agree with each other (box and
/// mean are the same uniform-average filter per the 0.3.0 contract).
///
/// The historical defects were format-specific: I420 used a shrinking window
/// at the border and never blurred chroma at all (a Dart-side wiring gap, not
/// a native one); NV21 used `radius / 2` instead of `radius` for the kernel
/// size and could read already-blurred chroma samples back into a later
/// average because it wrote in place during the same pass.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  YuvImage patternI420(int width, int height) {
    final uvW = (width + 1) ~/ 2, uvH = (height + 1) ~/ 2;
    final y = Uint8List(width * height);
    final u = Uint8List(uvW * uvH);
    final v = Uint8List(uvW * uvH);
    for (int i = 0; i < y.length; i++) {
      y[i] = (i * 7) & 0xFF;
    }
    for (int i = 0; i < u.length; i++) {
      u[i] = (i * 11) & 0xFF;
      v[i] = (i * 13) & 0xFF;
    }
    return YuvImage(YuvFileFormat.i420, width, height, planes: [YuvPlane(height, width, 1, y), YuvPlane(uvH, uvW, 1, u), YuvPlane(uvH, uvW, 1, v)]);
  }

  /// Same content as [patternI420], but every plane carries a padded row
  /// stride and a `pixelStride` of 2 (one gap byte after every sample). The
  /// gap bytes are filled with a sentinel so a test can assert they survive
  /// blur untouched.
  YuvImage patternI420Padded(int width, int height, {int gapByte = 0xEE}) {
    final uvW = (width + 1) ~/ 2, uvH = (height + 1) ~/ 2;
    final yRowStride = width * 2;
    final uvRowStride = uvW * 2;
    final y = Uint8List(height * yRowStride)..fillRange(0, height * yRowStride, gapByte);
    final u = Uint8List(uvH * uvRowStride)..fillRange(0, uvH * uvRowStride, gapByte);
    final v = Uint8List(uvH * uvRowStride)..fillRange(0, uvH * uvRowStride, gapByte);
    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        y[row * yRowStride + col * 2] = ((row * width + col) * 7) & 0xFF;
      }
    }
    for (int row = 0; row < uvH; row++) {
      for (int col = 0; col < uvW; col++) {
        final i = row * uvW + col;
        u[row * uvRowStride + col * 2] = (i * 11) & 0xFF;
        v[row * uvRowStride + col * 2] = (i * 13) & 0xFF;
      }
    }
    return YuvImage(
      YuvFileFormat.i420,
      width,
      height,
      planes: [YuvPlane(height, yRowStride, 2, y), YuvPlane(uvH, uvRowStride, 2, u), YuvPlane(uvH, uvRowStride, 2, v)],
    );
  }

  YuvImage patternNv21(int width, int height) {
    final uvW = (width + 1) ~/ 2, uvH = (height + 1) ~/ 2;
    final y = Uint8List(width * height);
    final uv = Uint8List(uvW * uvH * 2);
    for (int i = 0; i < y.length; i++) {
      y[i] = (i * 7) & 0xFF;
    }
    for (int i = 0; i < uv.length; i++) {
      uv[i] = (i * 11) & 0xFF;
    }
    return YuvImage(YuvFileFormat.nv21, width, height, planes: [YuvPlane(height, width, 1, y), YuvPlane(uvH, uvW * 2, 2, uv)]);
  }

  /// Same content as [patternNv21], but with an additional row-stride pad on
  /// top of the format's inherent chroma `pixelStride` of 2. Gap bytes are
  /// filled with a sentinel so a test can assert they survive blur untouched.
  YuvImage patternNv21Padded(int width, int height, {int gapByte = 0xEE}) {
    final uvW = (width + 1) ~/ 2, uvH = (height + 1) ~/ 2;
    final yRowStride = width + 4;
    final uvRowStride = uvW * 2 + 4;
    final y = Uint8List(height * yRowStride)..fillRange(0, height * yRowStride, gapByte);
    final uv = Uint8List(uvH * uvRowStride)..fillRange(0, uvH * uvRowStride, gapByte);
    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        y[row * yRowStride + col] = ((row * width + col) * 7) & 0xFF;
      }
    }
    for (int row = 0; row < uvH; row++) {
      for (int col = 0; col < uvW * 2; col++) {
        uv[row * uvRowStride + col] = ((row * uvW * 2 + col) * 11) & 0xFF;
      }
    }
    return YuvImage(YuvFileFormat.nv21, width, height, planes: [YuvPlane(height, yRowStride, 1, y), YuvPlane(uvH, uvRowStride, 2, uv)]);
  }

  group('I420', () {
    test('radius == 0 is a no-op', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      final image = patternI420(16, 16);
      final beforeY = Uint8List.fromList(image.yPlane.bytes);
      final beforeU = Uint8List.fromList(image.uPlane.bytes);
      final beforeV = Uint8List.fromList(image.vPlane.bytes);

      image.boxBlur(radius: 0);

      expect(image.yPlane.bytes, orderedEquals(beforeY));
      expect(image.uPlane.bytes, orderedEquals(beforeU));
      expect(image.vPlane.bytes, orderedEquals(beforeV));
    });

    test('an empty ROI is a no-op', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      final image = patternI420(16, 16);
      final before = Uint8List.fromList(image.yPlane.bytes);

      image.boxBlur(radius: 3, rect: const ui.Rect.fromLTRB(8, 8, 8, 8));

      expect(image.yPlane.bytes, orderedEquals(before));
    });

    test('pixels outside the ROI keep their original Y bytes', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      final image = patternI420(16, 16);
      final before = Uint8List.fromList(image.yPlane.bytes);

      image.boxBlur(radius: 2, rect: const ui.Rect.fromLTRB(4, 4, 8, 8));

      for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
          final inRoi = x >= 4 && x < 8 && y >= 4 && y < 8;
          if (inRoi) continue;
          expect(image.yPlane.bytes[y * 16 + x], before[y * 16 + x], reason: 'pixel ($x, $y) lies outside the ROI');
        }
      }
    });

    test('boxBlur and meanBlur agree on every plane', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      final boxed = patternI420(20, 20)..boxBlur(radius: 3);
      final meaned = patternI420(20, 20)..meanBlur(radius: 3);

      expect(boxed.yPlane.bytes, orderedEquals(meaned.yPlane.bytes));
      expect(boxed.uPlane.bytes, orderedEquals(meaned.uPlane.bytes));
      expect(boxed.vPlane.bytes, orderedEquals(meaned.vPlane.bytes));
    });

    test('chroma actually changes: box/mean blur is not a Y-only operation', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      // Regression guard for the historical Dart-side wiring gap: native
      // chroma blur ran, but the wrapper never copied `u`/`v` back out of the
      // FFI struct, so the Dart planes stayed exactly as constructed no
      // matter what the native code did.
      final image = patternI420(16, 16);
      final beforeU = Uint8List.fromList(image.uPlane.bytes);
      final beforeV = Uint8List.fromList(image.vPlane.bytes);

      image.boxBlur(radius: 3);

      expect(image.uPlane.bytes, isNot(orderedEquals(beforeU)));
      expect(image.vPlane.bytes, isNot(orderedEquals(beforeV)));
    });

    test('a padded pixelStride > 1 plane blurs the same samples as a tight one, gaps untouched', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      // yuv_box_blur_v1's scratch packing walks src/dst by
      // rowStride/pixelStride rather than memcpy-ing whole rows, so a
      // pixelStride > 1 plane is a genuinely different code path from the
      // tight-stride cases above, not just a relabeling of the same bytes.
      const width = 16, height = 16;
      final tight = patternI420(width, height)..boxBlur(radius: 3);
      final padded = patternI420Padded(width, height)..boxBlur(radius: 3);

      final uvW = (width + 1) ~/ 2, uvH = (height + 1) ~/ 2;
      for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
          expect(padded.yPlane.bytes[row * width * 2 + col * 2], tight.yPlane.bytes[row * width + col], reason: 'Y sample ($col, $row)');
          expect(padded.yPlane.bytes[row * width * 2 + col * 2 + 1], 0xEE, reason: 'Y gap byte ($col, $row) must stay untouched');
        }
      }
      for (int row = 0; row < uvH; row++) {
        for (int col = 0; col < uvW; col++) {
          expect(padded.uPlane.bytes[row * uvW * 2 + col * 2], tight.uPlane.bytes[row * uvW + col], reason: 'U sample ($col, $row)');
          expect(padded.vPlane.bytes[row * uvW * 2 + col * 2], tight.vPlane.bytes[row * uvW + col], reason: 'V sample ($col, $row)');
          expect(padded.uPlane.bytes[row * uvW * 2 + col * 2 + 1], 0xEE, reason: 'U gap byte ($col, $row) must stay untouched');
          expect(padded.vPlane.bytes[row * uvW * 2 + col * 2 + 1], 0xEE, reason: 'V gap byte ($col, $row) must stay untouched');
        }
      }
    });
  });

  group('NV21', () {
    test('radius == 0 is a no-op', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      final image = patternNv21(16, 16);
      final beforeY = Uint8List.fromList(image.yPlane.bytes);
      final beforeUv = Uint8List.fromList(image.uPlane.bytes);

      image.boxBlur(radius: 0);

      expect(image.yPlane.bytes, orderedEquals(beforeY));
      expect(image.uPlane.bytes, orderedEquals(beforeUv));
    });

    test('an empty ROI is a no-op', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      final image = patternNv21(16, 16);
      final before = Uint8List.fromList(image.yPlane.bytes);

      image.boxBlur(radius: 3, rect: const ui.Rect.fromLTRB(8, 8, 8, 8));

      expect(image.yPlane.bytes, orderedEquals(before));
    });

    test('pixels outside the ROI keep their original Y bytes', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      final image = patternNv21(16, 16);
      final before = Uint8List.fromList(image.yPlane.bytes);

      image.boxBlur(radius: 2, rect: const ui.Rect.fromLTRB(4, 4, 8, 8));

      for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
          final inRoi = x >= 4 && x < 8 && y >= 4 && y < 8;
          if (inRoi) continue;
          expect(image.yPlane.bytes[y * 16 + x], before[y * 16 + x], reason: 'pixel ($x, $y) lies outside the ROI');
        }
      }
    });

    test('boxBlur and meanBlur agree on every plane', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      final boxed = patternNv21(20, 20)..boxBlur(radius: 3);
      final meaned = patternNv21(20, 20)..meanBlur(radius: 3);

      expect(boxed.yPlane.bytes, orderedEquals(meaned.yPlane.bytes));
      expect(boxed.uPlane.bytes, orderedEquals(meaned.uPlane.bytes));
    });

    test('repeated runs on identical input produce identical output', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      // Regression guard for the historical in-place chroma hazard: unpacking
      // into scratch planes and blurring those, rather than blurring the
      // interleaved plane in place, is what makes repeated runs deterministic.
      final a = patternNv21(24, 24)..boxBlur(radius: 4, rect: const ui.Rect.fromLTRB(4, 4, 20, 20));
      final b = patternNv21(24, 24)..boxBlur(radius: 4, rect: const ui.Rect.fromLTRB(4, 4, 20, 20));

      expect(a.yPlane.bytes, orderedEquals(b.yPlane.bytes));
      expect(a.uPlane.bytes, orderedEquals(b.uPlane.bytes));
    });

    test('a padded row stride blurs the same samples as a tight one, gaps untouched', () {
      if (!nativeAvailable) {
        markTestSkipped('native library is not available on this host');
        return;
      }
      // yuv_box_blur_v1's Y-plane scratch packing walks src/dst by
      // rowStride rather than memcpy-ing a whole tight plane in one call, so a
      // padded row stride is a genuinely different code path from the tight
      // cases above. The interleaved chroma plane already has an inherent
      // pixelStride of 2 (deinterleave/reinterleave), so this exercises an
      // additional row-stride pad on top of that.
      const width = 16, height = 16;
      final tight = patternNv21(width, height)..boxBlur(radius: 3);
      final padded = patternNv21Padded(width, height)..boxBlur(radius: 3);

      final uvW = (width + 1) ~/ 2, uvH = (height + 1) ~/ 2;
      final paddedYStride = width + 4;
      final paddedUvStride = uvW * 2 + 4;
      for (int row = 0; row < height; row++) {
        for (int col = 0; col < width; col++) {
          expect(padded.yPlane.bytes[row * paddedYStride + col], tight.yPlane.bytes[row * width + col], reason: 'Y sample ($col, $row)');
        }
        for (int col = width; col < paddedYStride; col++) {
          expect(padded.yPlane.bytes[row * paddedYStride + col], 0xEE, reason: 'Y gap byte at row $row, col $col must stay untouched');
        }
      }
      for (int row = 0; row < uvH; row++) {
        for (int col = 0; col < uvW * 2; col++) {
          expect(padded.uPlane.bytes[row * paddedUvStride + col], tight.uPlane.bytes[row * uvW * 2 + col], reason: 'UV sample ($col, $row)');
        }
        for (int col = uvW * 2; col < paddedUvStride; col++) {
          expect(padded.uPlane.bytes[row * paddedUvStride + col], 0xEE, reason: 'UV gap byte at row $row, col $col must stay untouched');
        }
      }
    });
  });

  test('an invalid radius is rejected before reaching native code, for I420 and NV21', () {
    // Regression guard for the general P1 review finding on 2026-09-20:
    // boxBlur/meanBlur passed any radius straight to C without validation. A
    // negative radius inverts the SAT rectangle bounds and reads/writes out
    // of bounds; this does not need nativeAvailable, since validation
    // happens in Dart before any native call or allocation.
    final i420 = patternI420(8, 8);
    expect(() => i420.boxBlur(radius: -1), throwsArgumentError);
    expect(() => i420.meanBlur(radius: -1), throwsArgumentError);
    expect(() => i420.boxBlur(radius: 257), throwsArgumentError);
    expect(() => i420.meanBlur(radius: 257), throwsArgumentError);

    final nv21 = patternNv21(8, 8);
    expect(() => nv21.boxBlur(radius: -1), throwsArgumentError);
    expect(() => nv21.meanBlur(radius: -1), throwsArgumentError);
    expect(() => nv21.boxBlur(radius: 257), throwsArgumentError);
    expect(() => nv21.meanBlur(radius: 257), throwsArgumentError);
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
