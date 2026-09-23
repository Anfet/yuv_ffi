import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Web counterpart of `test/rel05_independent_results_test.dart`: REL-05's
/// aliasing, padded BGRA, and semantic-no-op contracts hold the same way on
/// the WASM backend, per `doc/api-abi-0.4-design.md` sections 4 and 13
/// ("Both runners follow" the same eight-step publish contract).
///
/// Follows the existing `test/web/wasm_parity_*` convention: skipped with a
/// passing placeholder on a non-browser runtime, so this file participates in
/// the normal `flutter test` run everywhere and only exercises the real WASM
/// module under `flutter test -p chrome`.
void main() {
  if (!kIsWeb) {
    test('REL-05 web parity tests are skipped on non-web runtime', () {
      expect(true, isTrue);
    });
    return;
  }

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await YuvFfi.ensureInitialized();
  });

  group('byte-level correctness', () {
    test('toI420()/toNv12()/toBgra() round-trip a solid color within tolerance', () {
      const int w = 4;
      const int h = 4;
      final rgba = _solidRgba(w, h, r: 10, g: 20, b: 30);
      final bgra = YuvImage.bgra(w, h)..fromRgba8888(rgba);

      final i420 = bgra.toI420();
      expect(i420.format, YuvFileFormat.i420);
      expect(i420.yPlane.bytes.toSet(), hasLength(1));

      final nv12 = bgra.toNv12();
      expect(nv12.format, YuvFileFormat.nv21);
      expect(nv12.yPlane.bytes.toSet(), hasLength(1));

      final roundTrip = i420.toBgra();
      _expectSolidBgra(roundTrip.toBgraBytes(), w, h, r: 10, g: 20, b: 30, tolerance: 20);
    });
  });

  group('padded BGRA', () {
    test('toBgraBytes() on a padded BGRA source packs tight bytes without corrupting padding', () {
      const int w = 3;
      const int h = 5;
      const int rowStride = w * 4 + 8;
      const int pixelStride = 4;

      final backing = Uint8List(h * rowStride)..fillRange(0, h * rowStride, 0xA5);
      for (int row = 0; row < h; row++) {
        for (int col = 0; col < w; col++) {
          final offset = row * rowStride + col * pixelStride;
          backing[offset] = 40;
          backing[offset + 1] = 80;
          backing[offset + 2] = 160;
          backing[offset + 3] = 255;
        }
      }
      final plane = YuvPlane(h, rowStride, pixelStride, backing);
      final padded = YuvImage.bgra(w, h, planes: [plane]);

      final tightBytes = padded.toBgraBytes();

      expect(tightBytes.length, w * h * 4);
      for (int row = 0; row < h; row++) {
        for (int col = 0; col < w; col++) {
          final offset = (row * w + col) * 4;
          expect(tightBytes.sublist(offset, offset + 4), orderedEquals(<int>[40, 80, 160, 255]));
        }
      }
      expect(tightBytes.toSet().contains(0xA5), isFalse);
    });
  });

  group('aliasing', () {
    test('toI420()/toNv12()/toBgra() results are unaffected by mutating the source afterwards', () {
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

      source.applyNegate();

      expect(i420.getBytes(), i420Before);
      expect(nv12.getBytes(), nv12Before);
      expect(bgraCopy.getBytes(), bgraBefore);
    });

    test('cropped()/rotated() results are unaffected by mutating the source afterwards', () {
      const int w = 6;
      const int h = 6;
      final rgba = _solidRgba(w, h, r: 9, g: 8, b: 7);
      final source = YuvImage.bgra(w, h)..fromRgba8888(rgba);

      final crop = source.cropped(const ui.Rect.fromLTWH(1, 1, 3, 3));
      final rotate = source.rotated(YuvImageRotation.rotation90);
      final cropBefore = crop.getBytes();
      final rotateBefore = rotate.getBytes();

      source.applyNegate();

      expect(crop.getBytes(), cropBefore);
      expect(rotate.getBytes(), rotateBefore);
    });
  });

  group('toBytes()/toBgraBytes() never expose backing storage', () {
    test('toBytes() returns a copy', () {
      final image = YuvImage.i420(4, 4);
      final bytes = image.toBytes();
      final beforeAnyMutation = Uint8List.fromList(bytes);

      bytes[0] = bytes[0] ^ 0xFF;
      expect(image.toBytes(), beforeAnyMutation);

      image.yPlane.bytes[1] = image.yPlane.bytes[1] ^ 0xFF;
      image.markDirty();
      expect(image.toBytes()[1], isNot(beforeAnyMutation[1]));
      expect(bytes[1], beforeAnyMutation[1]);
    });

    test('toBgraBytes() returns a copy', () {
      final image = YuvImage.bgra(4, 4);
      final bytes = image.toBgraBytes();
      final before = Uint8List.fromList(bytes);

      bytes[0] = bytes[0] ^ 0xFF;

      expect(image.toBgraBytes(), before);
    });
  });

  group('semantic no-op returns an independent deep copy', () {
    test('toNv12()/toBgra() on an already-matching format return an independent copy', () {
      final nv12 = YuvImage.nv12(4, 4);
      final nv12Revision = (nv12 as YuvRevisionAware).internalRevision;
      final nv12Result = nv12.toNv12();
      expect(identical(nv12Result, nv12), isFalse);
      expect((nv12 as YuvRevisionAware).internalRevision, nv12Revision);

      final bgra = YuvImage.bgra(4, 4);
      final bgraRevision = (bgra as YuvRevisionAware).internalRevision;
      final bgraResult = bgra.toBgra();
      expect(identical(bgraResult, bgra), isFalse);
      expect((bgra as YuvRevisionAware).internalRevision, bgraRevision);
    });

    test('cropped() with a full-frame region returns an independent copy', () {
      final image = YuvImage.bgra(4, 4);
      final revisionBefore = (image as YuvRevisionAware).internalRevision;

      final result = image.cropped(const ui.Rect.fromLTWH(0, 0, 4, 4));

      expect(identical(result, image), isFalse);
      expect((image as YuvRevisionAware).internalRevision, revisionBefore);
    });
  });
}

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

void _expectSolidBgra(Uint8List bytes, int w, int h, {required int r, required int g, required int b, required int tolerance}) {
  expect(bytes.length, w * h * 4);
  for (int i = 0; i < bytes.length; i += 4) {
    expect((bytes[i] - b).abs(), lessThanOrEqualTo(tolerance));
    expect((bytes[i + 1] - g).abs(), lessThanOrEqualTo(tolerance));
    expect((bytes[i + 2] - r).abs(), lessThanOrEqualTo(tolerance));
    expect(bytes[i + 3], 255);
  }
}
