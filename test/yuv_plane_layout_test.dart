import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies PACK-01B: the `layout` option every `planes`-accepting `YuvImage`
/// factory now takes, and its `YuvPlaneLayout.packed` default.
///
/// Runs without `YuvFfi.initialize()`: the layout decision happens in
/// `YuvImageState`'s constructor, in pure Dart, before any native/WASM call.
void main() {
  int deterministicByte(int seed, int index) => (index * 37 + seed) & 0xff;

  YuvPlane plane({
    required int rows,
    required int rowStride,
    required int columns,
    required int pixelStride,
    required int sampleBytes,
    required int seed,
  }) {
    final bytes = Uint8List(rows * rowStride);
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        for (var b = 0; b < sampleBytes; b++) {
          bytes[row * rowStride + col * pixelStride + b] = deterministicByte(seed + b, row * columns + col);
        }
      }
    }
    return YuvPlane(rows, rowStride, pixelStride, bytes);
  }

  group('YuvPlaneLayout.preserve keeps caller strides byte-for-byte', () {
    test('I420 with row-padded Y and chroma pixelStride 2 (Pixel 3 geometry)', () {
      const width = 8, height = 6;
      const chromaWidth = 4, chromaHeight = 3;
      final image = YuvImage.i420(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width + 16, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1),
          plane(rows: chromaHeight, rowStride: chromaWidth * 2, columns: chromaWidth, pixelStride: 2, sampleBytes: 1, seed: 2),
          plane(rows: chromaHeight, rowStride: chromaWidth * 2, columns: chromaWidth, pixelStride: 2, sampleBytes: 1, seed: 3),
        ],
        layout: YuvPlaneLayout.preserve,
      );

      expect(image.yPlane.rowStride, width + 16);
      expect(image.uPlane.rowStride, chromaWidth * 2);
      expect(image.uPlane.pixelStride, 2);
      expect(image.vPlane.rowStride, chromaWidth * 2);
      expect(image.vPlane.pixelStride, 2);
      expect(image.isTightlyPacked, isFalse);
    });

    test('NV12 with padded UV row stride', () {
      const width = 8, height = 6;
      const chromaWidth = 4, chromaHeight = 3;
      final image = YuvImage.nv12(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1),
          plane(rows: chromaHeight, rowStride: chromaWidth * 2 + 6, columns: chromaWidth, pixelStride: 2, sampleBytes: 2, seed: 2),
        ],
        layout: YuvPlaneLayout.preserve,
      );

      expect(image.uPlane.rowStride, chromaWidth * 2 + 6);
      expect(image.isTightlyPacked, isFalse);
    });

    test('BGRA with a padded row stride', () {
      const width = 5, height = 4;
      final image = YuvImage.bgra(
        width,
        height,
        planes: [plane(rows: height, rowStride: width * 4 + 8, columns: width, pixelStride: 4, sampleBytes: 4, seed: 1)],
        layout: YuvPlaneLayout.preserve,
      );

      expect(image.yPlane.rowStride, width * 4 + 8);
      expect(image.isTightlyPacked, isFalse);
    });

    test('deep-copies rather than aliasing the caller plane', () {
      final source = plane(rows: 2, rowStride: 24, columns: 2, pixelStride: 4, sampleBytes: 4, seed: 1);
      final image = YuvImage.bgra(2, 2, planes: [source], layout: YuvPlaneLayout.preserve);

      source.bytes[0] = 0xFF;

      expect(image.yPlane.bytes[0], isNot(0xFF), reason: 'preserve must still deep-copy, not alias, the caller plane');
    });
  });

  group('YuvPlaneLayout.packed (the default) tightens the layout at construction', () {
    test('I420: default with no explicit layout argument packs a padded source', () {
      const width = 8, height = 6;
      const chromaWidth = 4, chromaHeight = 3;
      final yBefore = plane(rows: height, rowStride: width + 16, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1);
      final uBefore = plane(rows: chromaHeight, rowStride: chromaWidth * 2, columns: chromaWidth, pixelStride: 2, sampleBytes: 1, seed: 2);
      final vBefore = plane(rows: chromaHeight, rowStride: chromaWidth * 2, columns: chromaWidth, pixelStride: 2, sampleBytes: 1, seed: 3);

      final image = YuvImage.i420(width, height, planes: [yBefore, uBefore, vBefore]);

      expect(image.isTightlyPacked, isTrue);
      expect(image.yPlane.rowStride, width);
      expect(image.uPlane.rowStride, chromaWidth);
      expect(image.uPlane.pixelStride, 1, reason: 'I420 chroma at pixelStride 2 must de-interleave to 1 under the packed default');
      expect(image.vPlane.pixelStride, 1);
      // Visible samples survive: row 0, col 0 of U/V came from byte 0 of each
      // padded chroma plane, at seed 2/3 respectively.
      expect(image.uPlane.bytes[0], uBefore.bytes[0]);
      expect(image.vPlane.bytes[0], vBefore.bytes[0]);
    });

    test('I420: explicit YuvPlaneLayout.packed matches the default', () {
      const width = 8, height = 6;
      final planes = [
        plane(rows: height, rowStride: width + 16, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1),
        plane(rows: 3, rowStride: 4 * 2, columns: 4, pixelStride: 2, sampleBytes: 1, seed: 2),
        plane(rows: 3, rowStride: 4 * 2, columns: 4, pixelStride: 2, sampleBytes: 1, seed: 3),
      ];
      final viaDefault = YuvImage.i420(width, height, planes: planes);
      final viaExplicit = YuvImage.i420(width, height, planes: planes, layout: YuvPlaneLayout.packed);

      expect(viaExplicit.yPlane.rowStride, viaDefault.yPlane.rowStride);
      expect(viaExplicit.uPlane.pixelStride, viaDefault.uPlane.pixelStride);
      expect(viaExplicit.isTightlyPacked, isTrue);
    });

    test('NV12: packed keeps interleaved UV at pixelStride 2, only removes row padding', () {
      const width = 8, height = 6;
      const chromaWidth = 4, chromaHeight = 3;
      final image = YuvImage.nv12(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1),
          plane(rows: chromaHeight, rowStride: chromaWidth * 2 + 6, columns: chromaWidth, pixelStride: 2, sampleBytes: 2, seed: 2),
        ],
      );

      expect(image.isTightlyPacked, isTrue);
      expect(image.uPlane.pixelStride, 2, reason: 'the interleaved (U, V) pair must not be split by the packed default');
      expect(image.uPlane.rowStride, chromaWidth * 2);
    });

    test('BGRA: packed removes row padding', () {
      const width = 5, height = 4;
      final image = YuvImage.bgra(
        width,
        height,
        planes: [plane(rows: height, rowStride: width * 4 + 8, columns: width, pixelStride: 4, sampleBytes: 4, seed: 1)],
      );

      expect(image.isTightlyPacked, isTrue);
      expect(image.yPlane.rowStride, width * 4);
    });

    test('an already tight source is unaffected (no spurious repack)', () {
      const width = 8, height = 6;
      final tightY = plane(rows: height, rowStride: width, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1);
      final tightU = plane(rows: 3, rowStride: 4, columns: 4, pixelStride: 1, sampleBytes: 1, seed: 2);
      final tightV = plane(rows: 3, rowStride: 4, columns: 4, pixelStride: 1, sampleBytes: 1, seed: 3);

      final image = YuvImage.i420(width, height, planes: [tightY, tightU, tightV]);

      expect(image.yPlane.bytes, orderedEquals(tightY.bytes));
      expect(image.uPlane.bytes, orderedEquals(tightU.bytes));
      expect(image.vPlane.bytes, orderedEquals(tightV.bytes));
    });
  });

  group('layout is ignored when planes is omitted -- an allocated image is always tight', () {
    test('explicit yPixelStride/uvPixelStride still control allocation regardless of layout', () {
      final image = YuvImage.i420(4, 4, yPixelStride: 1, uvPixelStride: 1, layout: YuvPlaneLayout.preserve);
      expect(image.isTightlyPacked, isTrue);
      expect(image.yPlane.rowStride, 4);
    });
  });

  group('internal paths keep the caller/source layout regardless of the new default', () {
    test('copy(blank: true) keeps a padded source\'s declared geometry, zero-filled', () {
      final source = plane(rows: 2, rowStride: 16, columns: 2, pixelStride: 4, sampleBytes: 4, seed: 1);
      final image = YuvImage.bgra(2, 2, planes: [source], layout: YuvPlaneLayout.preserve);

      // ignore: deprecated_member_use_from_same_package
      final blank = image.copy(blank: true);

      expect(blank.yPlane.rowStride, 16, reason: 'a blank copy must not silently repack a padded source');
      expect(blank.yPlane.bytes.every((b) => b == 0), isTrue);
    });

    test('copy() keeps a padded source\'s layout and content', () {
      final source = plane(rows: 2, rowStride: 16, columns: 2, pixelStride: 4, sampleBytes: 4, seed: 1);
      final image = YuvImage.bgra(2, 2, planes: [source], layout: YuvPlaneLayout.preserve);

      final copy = image.copy();

      expect(copy.yPlane.rowStride, 16);
      expect(copy.yPlane.bytes, orderedEquals(image.yPlane.bytes));
    });

    test('encodeTo()/decode() round-trip keeps the source\'s padded layout', () async {
      final source = plane(rows: 2, rowStride: 16, columns: 2, pixelStride: 4, sampleBytes: 4, seed: 1);
      final image = YuvImage.bgra(2, 2, planes: [source], layout: YuvPlaneLayout.preserve);

      final chunks = <List<int>>[];
      await image.encodeTo(_CollectingSink(chunks));
      final decoded = await YuvImage.decode(Stream<List<int>>.fromIterable(chunks));

      expect(decoded.yPlane.rowStride, 16, reason: 'decode() must not silently repack the encoded layout under the new packed default');
      expect(decoded.yPlane.bytes, orderedEquals(image.yPlane.bytes));
    });
  });
}

class _CollectingSink implements Sink<List<int>> {
  _CollectingSink(this.chunks);

  final List<List<int>> chunks;

  @override
  void add(List<int> data) => chunks.add(data);

  @override
  void close() {}
}
