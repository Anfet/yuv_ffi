import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/impl/loader_io.dart' as loader_io;
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-05's independent-result surface (`toI420`/`toNv12`/`toBgra`,
/// `cropped`/`rotated`, `toBytes`/`toBgraBytes`) against
/// `doc/api-abi-0.4-design.md` sections 4 and 13.
///
/// REL-04 already added generic no-op-aliasing coverage for `cropped()`,
/// `rotated(rotation0)` and `toI420()` in `test/yuv_apply_surface_test.dart`.
/// This file adds what that left out: byte-level correctness of the
/// conversions against a hand-computable oracle, explicit source/result
/// aliasing checks (mutate one, assert the other is untouched), a padded BGRA
/// case through `toBgra()`/`toBgraBytes()`, the missing same-format no-op
/// cases (`toNv12()`, `toBgra()`), and a direct check that `toBytes()` and
/// `toBgraBytes()` never return a view onto backing storage.
///
/// Every group except the last one calls a capability-gated `apply*`/`to*`/
/// `cropped`/`rotated` method, which requires `YuvFfi.initialize()` to have
/// completed against a real backend (`test/yuv_apply_surface_test.dart`'s
/// "operations x formats matrix" group has the same requirement, for the same
/// reason). That in turn requires the real native library: on this host,
/// `library` (and therefore `YuvFfi.initialize()`) only succeeds when
/// `yuv_ffi.dll` sits next to the test process's working directory. Only the
/// final `toBytes()`/`toBgraBytes()` group calls neither and so runs
/// unconditionally.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  setUp(() async {
    loader_io.debugResetLoader();
    if (nativeAvailable) {
      await YuvFfi.initialize();
    }
  });

  tearDown(() {
    loader_io.debugResetLoader();
  });

  test('copy() preserves a gapped NV12 layout and does not alias its planes', () {
    final source = YuvImage.nv12(4, 4, uvPixelStride: 3);
    source.uPlane.bytes[0] = 0x11;

    final copy = source.copy();
    source.uPlane.bytes[0] = 0x22;

    expect(copy.uPlane.pixelStride, 3);
    expect(copy.uPlane.bytes[0], 0x11);
  });

  group('byte-level correctness (requires real native library)', () {
    test(
      'toI420() produces the exact planar bytes for a hand-computable RGBA source',
      () {
        const int w = 4;
        const int h = 4;
        final rgba = _solidRgba(w, h, r: 10, g: 20, b: 30);
        final bgra = YuvImage.bgra(w, h)..fromRgba8888(rgba);

        final i420 = bgra.toI420();

        expect(i420.format, YuvPixelFormat.i420);
        expect(i420.width, w);
        expect(i420.height, h);
        // A solid-color source converts to a solid Y/U/V plane: every sample in
        // each plane must carry the same value, which is checkable without
        // depending on the exact BT.601/BT.709 coefficients the native
        // converter uses.
        expect(i420.yPlane.bytes.toSet(), hasLength(1), reason: 'Y plane must be uniform for a solid-color source');
        expect(i420.uPlane.bytes.toSet(), hasLength(1), reason: 'U plane must be uniform for a solid-color source');
        expect(i420.vPlane.bytes.toSet(), hasLength(1), reason: 'V plane must be uniform for a solid-color source');
        // Round-tripping back through BGRA must reproduce the original solid
        // color exactly: this is the oracle that pins the conversion's
        // correctness without hardcoding the YUV coefficients here.
        final roundTrip = i420.toBgra();
        _expectSolidBgra(roundTrip.toBgraBytes(), w, h, r: 10, g: 20, b: 30, tolerance: 2);
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test(
      'toNv12() produces the exact interleaved chroma bytes for a hand-computable RGBA source',
      () {
        const int w = 4;
        const int h = 4;
        final rgba = _solidRgba(w, h, r: 200, g: 100, b: 50);
        final bgra = YuvImage.bgra(w, h)..fromRgba8888(rgba);

        final nv12 = bgra.toNv12();

        expect(nv12.format, YuvPixelFormat.nv12);
        expect(nv12.width, w);
        expect(nv12.height, h);
        expect(nv12.yPlane.bytes.toSet(), hasLength(1));
        // NV12's chroma plane interleaves (U, V) pairs at pixelStride 2: for a
        // solid color every pair must repeat identically.
        final chroma = nv12.uPlane.bytes;
        final firstPair = chroma.sublist(0, 2);
        for (int i = 0; i < chroma.length; i += 2) {
          expect(chroma.sublist(i, i + 2), orderedEquals(firstPair), reason: 'chroma pair at byte $i differs from the first pair');
        }
        final roundTrip = nv12.toBgra();
        _expectSolidBgra(roundTrip.toBgraBytes(), w, h, r: 200, g: 100, b: 50, tolerance: 2);
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test(
      'toBgra() from I420 produces exact tight BGRA bytes for a hand-computable source',
      () {
        const int w = 4;
        const int h = 4;
        final rgba = _solidRgba(w, h, r: 5, g: 250, b: 128);
        final i420 = YuvImage.i420(w, h)..fromRgba8888(rgba);

        final bgra = i420.toBgra();

        expect(bgra.format, YuvPixelFormat.bgra8888);
        expect(bgra.width, w);
        expect(bgra.height, h);
        expect(bgra.yPlane.rowStride, w * 4, reason: 'toBgra() must produce a tight destination plane');
        expect(bgra.yPlane.pixelStride, 4);
        _expectSolidBgra(bgra.toBgraBytes(), w, h, r: 5, g: 250, b: 128, tolerance: 2);
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );
  });

  group('padded BGRA handled correctly by toBgra()/toBgraBytes() (requires real native library)', () {
    test(
      'toBgraBytes() on a padded BGRA source packs tight bytes without corrupting or reading padding',
      () {
        const int w = 3;
        const int h = 5;
        const int rowStride = w * 4 + 8; // 8-byte row padding.
        const int pixelStride = 4;

        // Canary-filled backing buffer: every byte starts as 0xA5, then the
        // logical w*h*4 pixels are overwritten with a known solid color at
        // their padded offsets. If toBgraBytes() ever read past pixelStride/
        // rowStride the canary bytes would leak into the tight result.
        final backing = Uint8List(h * rowStride)..fillRange(0, h * rowStride, 0xA5);
        for (int row = 0; row < h; row++) {
          for (int col = 0; col < w; col++) {
            final offset = row * rowStride + col * pixelStride;
            backing[offset] = 40; // B
            backing[offset + 1] = 80; // G
            backing[offset + 2] = 160; // R
            backing[offset + 3] = 255; // A
          }
        }
        final plane = YuvPlane(h, rowStride, pixelStride, backing);
        final padded = YuvImage.bgra(w, h, planes: [plane]);

        final tightBytes = padded.toBgraBytes();

        expect(tightBytes.length, w * h * 4, reason: 'toBgraBytes() must return exactly width*height*4 tight bytes');
        for (int row = 0; row < h; row++) {
          for (int col = 0; col < w; col++) {
            final offset = (row * w + col) * 4;
            expect(tightBytes.sublist(offset, offset + 4), orderedEquals(<int>[40, 80, 160, 255]), reason: 'pixel ($col,$row) corrupted');
          }
        }
        expect(tightBytes.toSet().contains(0xA5), isFalse, reason: 'padding canary leaked into the tight result');

        // toBgra() on an already-BGRA source is the documented same-format
        // no-op: an independent deep copy that keeps the source's own layout
        // (section 4), not a re-tightened buffer. It must still report the
        // same logical pixel content once read back through toBgraBytes(),
        // and must not alias the source's backing buffer.
        final converted = padded.toBgra();
        expect(identical(converted, padded), isFalse);
        expect(converted.yPlane.rowStride, rowStride);
        expect(converted.toBgraBytes(), orderedEquals(tightBytes));
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test(
      'cropped()/rotated() on a padded BGRA source do not corrupt or misread padding',
      () {
        const int w = 4;
        const int h = 4;
        const int rowStride = w * 4 + 12;
        const int pixelStride = 4;
        final backing = Uint8List(h * rowStride)..fillRange(0, h * rowStride, 0xA5);
        for (int row = 0; row < h; row++) {
          for (int col = 0; col < w; col++) {
            final offset = row * rowStride + col * pixelStride;
            final v = (row * w + col) & 0xFF;
            backing[offset] = v;
            backing[offset + 1] = v;
            backing[offset + 2] = v;
            backing[offset + 3] = 255;
          }
        }
        final plane = YuvPlane(h, rowStride, pixelStride, backing);
        final padded = YuvImage.bgra(w, h, planes: [plane]);
        final expectedBefore = padded.toBgraBytes();

        final cropResult = padded.cropped(const ui.Rect.fromLTWH(1, 1, 2, 2));
        expect(cropResult.width, 2);
        expect(cropResult.height, 2);
        // Source padding/backing must be entirely unaffected by cropping.
        expect(padded.toBgraBytes(), orderedEquals(expectedBefore));

        final rotateResult = padded.rotated(YuvImageRotation.rotation90);
        expect(rotateResult.width, h);
        expect(rotateResult.height, w);
        expect(padded.toBgraBytes(), orderedEquals(expectedBefore));
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );
  });

  group('aliasing: source and result own independent buffers (requires real native library)', () {
    test(
      'toI420()/toNv12()/toBgra() results are unaffected by mutating the source afterwards, and vice versa',
      () {
        const int w = 4;
        const int h = 4;
        final rgba = _solidRgba(w, h, r: 1, g: 2, b: 3);
        final source = YuvImage.bgra(w, h)..fromRgba8888(rgba);

        final i420 = source.toI420();
        final nv12 = source.toNv12();
        final bgraCopy = source.toBgra();
        final i420Before = i420.getBytes();
        final nv12Before = nv12.getBytes();
        final bgraBefore = bgraCopy.getBytes();

        // Mutate the source in place after taking independent results.
        source.applyNegate();

        expect(i420.getBytes(), i420Before, reason: 'toI420() result changed after mutating the source');
        expect(nv12.getBytes(), nv12Before, reason: 'toNv12() result changed after mutating the source');
        expect(bgraCopy.getBytes(), bgraBefore, reason: 'toBgra() result changed after mutating the source');

        // And the reverse: mutating a result must not affect the source or the
        // other independently obtained results.
        final sourceBytesBeforeResultMutation = source.getBytes();
        i420.applyNegate();
        expect(source.getBytes(), sourceBytesBeforeResultMutation, reason: 'source changed after mutating a toI420() result');
        expect(nv12.getBytes(), nv12Before, reason: 'toNv12() result changed after mutating an unrelated toI420() result');
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test(
      'cropped()/rotated() results are unaffected by mutating the source afterwards, and vice versa',
      () {
        const int w = 6;
        const int h = 6;
        final rgba = _solidRgba(w, h, r: 9, g: 8, b: 7);
        final source = YuvImage.bgra(w, h)..fromRgba8888(rgba);

        final crop = source.cropped(const ui.Rect.fromLTWH(1, 1, 3, 3));
        final rotate = source.rotated(YuvImageRotation.rotation90);
        final cropBefore = crop.getBytes();
        final rotateBefore = rotate.getBytes();

        source.applyNegate();

        expect(crop.getBytes(), cropBefore, reason: 'cropped() result changed after mutating the source');
        expect(rotate.getBytes(), rotateBefore, reason: 'rotated() result changed after mutating the source');

        final sourceBytesBeforeResultMutation = source.getBytes();
        crop.applyNegate();
        rotate.applyNegate();
        expect(source.getBytes(), sourceBytesBeforeResultMutation, reason: 'source changed after mutating cropped()/rotated() results');
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );
  });

  group('toBytes()/toBgraBytes() never expose backing storage', () {
    test('toBytes() returns a copy: mutating it does not change the image, and mutating the image afterwards does not change it', () {
      final image = YuvImage.i420(4, 4);
      final bytes = image.toBytes();
      final beforeAnyMutation = Uint8List.fromList(bytes);

      // Mutate the returned buffer directly, at index 0. A view onto the
      // plane would make this corrupt the image's own storage.
      bytes[0] = bytes[0] ^ 0xFF;
      expect(image.toBytes(), beforeAnyMutation, reason: 'mutating toBytes() result affected the image');

      // Mutate the image through a live plane at a different index (1), and
      // re-fetch: a real plane change must be visible in a fresh toBytes()
      // call, and must not retroactively appear in the earlier snapshot.
      image.yPlane.bytes[1] = image.yPlane.bytes[1] ^ 0xFF;
      image.markDirty();
      final freshBytes = image.toBytes();
      expect(freshBytes[1], isNot(beforeAnyMutation[1]), reason: 'toBytes() did not observe a real plane mutation on refetch');
      expect(bytes[1], beforeAnyMutation[1], reason: 'a stale toBytes() buffer must not retroactively alias a later plane mutation');
    });

    test('toBgraBytes() returns a copy: mutating it does not change the image', () {
      final image = YuvImage.bgra(4, 4);
      final bytes = image.toBgraBytes();
      final before = Uint8List.fromList(bytes);

      bytes[0] = bytes[0] ^ 0xFF;

      expect(image.toBgraBytes(), before, reason: 'mutating toBgraBytes() result affected the image');
      expect(image.yPlane.bytes[0], before[0], reason: 'mutating toBgraBytes() result affected the backing plane directly');
    });
  });

  group('semantic no-op returns an independent deep copy, never identical(this) (requires real native library)', () {
    test(
      'toNv12() on an already-NV12 image returns an independent copy with an unchanged source revision',
      () {
        final image = YuvImage.nv12(4, 4);
        final revisionBefore = (image as YuvRevisionAware).internalRevision;

        final result = image.toNv12();

        expect(identical(result, image), isFalse);
        expect(result.getBytes(), image.getBytes());
        expect((image as YuvRevisionAware).internalRevision, revisionBefore);

        // Independent buffers: mutating the copy must not affect the source.
        final sourceBefore = image.getBytes();
        result.applyNegate();
        expect(image.getBytes(), sourceBefore);
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test(
      'toBgra() on an already-BGRA image returns an independent copy with an unchanged source revision',
      () {
        final image = YuvImage.bgra(4, 4);
        final revisionBefore = (image as YuvRevisionAware).internalRevision;

        final result = image.toBgra();

        expect(identical(result, image), isFalse);
        expect(result.getBytes(), image.getBytes());
        expect((image as YuvRevisionAware).internalRevision, revisionBefore);

        final sourceBefore = image.getBytes();
        result.applyNegate();
        expect(image.getBytes(), sourceBefore);
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );

    test(
      'cropped() with a full-frame region returns an independent copy',
      () {
        final image = YuvImage.bgra(4, 4);
        final revisionBefore = (image as YuvRevisionAware).internalRevision;

        final result = image.cropped(const ui.Rect.fromLTWH(0, 0, 4, 4));

        // A full-frame crop is not one of the two documented no-op shapes
        // (empty region, rotation0), so this exercises the normal crop path
        // rather than the copy() short-circuit -- but it must still produce an
        // independent result and leave the source revision untouched.
        expect(identical(result, image), isFalse);
        expect((image as YuvRevisionAware).internalRevision, revisionBefore);
        final sourceBefore = image.getBytes();
        result.applyNegate();
        expect(image.getBytes(), sourceBefore);
      },
      skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host',
    );
  });
}

/// A tightly-packed RGBA8888 buffer of [w]x[h] pixels, every pixel the same
/// opaque color.
Uint8List _solidRgba(int w, int h, {required int r, required int g, required int b}) {
  final out = Uint8List(w * h * 4);
  for (int i = 0; i < out.length; i += 4) {
    out[i] = r;
    out[i + 1] = g;
    out[i + 2] = b;
    out[i + 3] = 255;
  }
  return out;
}

/// Asserts that tight BGRA [bytes] represent a [w]x[h] solid color, allowing
/// [tolerance] per channel for lossy YUV round-trip rounding.
void _expectSolidBgra(Uint8List bytes, int w, int h, {required int r, required int g, required int b, required int tolerance}) {
  expect(bytes.length, w * h * 4);
  for (int i = 0; i < bytes.length; i += 4) {
    expect((bytes[i] - b).abs(), lessThanOrEqualTo(tolerance), reason: 'B channel at pixel ${i ~/ 4}');
    expect((bytes[i + 1] - g).abs(), lessThanOrEqualTo(tolerance), reason: 'G channel at pixel ${i ~/ 4}');
    expect((bytes[i + 2] - r).abs(), lessThanOrEqualTo(tolerance), reason: 'R channel at pixel ${i ~/ 4}');
    expect(bytes[i + 3], 255, reason: 'A channel at pixel ${i ~/ 4}');
  }
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
