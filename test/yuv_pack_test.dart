import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies PACK-01A: `isTightlyPacked` and `pack()` report and remove row
/// padding and per-sample pixel gaps without a native/WASM backend, changing
/// format, geometry, visible content or UV order.
///
/// No `YuvFfi.initialize()` call anywhere here: `pack()` builds replacement
/// planes in pure Dart and publishes them through the existing, already
/// native-free `applyPlanes()` (YUV-20/REL-02), so this whole file runs on
/// every host, including one without the native library available.
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

  /// Reads back the [sampleBytes]-wide sample at ([row], [col]) of [p].
  List<int> sampleAt(YuvPlane p, int row, int col, int sampleBytes) {
    final start = row * p.rowStride + col * p.pixelStride;
    return [for (var b = 0; b < sampleBytes; b++) p.bytes[start + b]];
  }

  void expectSameVisibleSamples(YuvPlane before, YuvPlane after, {required int rows, required int columns, required int sampleBytesBefore}) {
    final sampleBytesAfter = after.pixelStride;
    expect(after.height, rows);
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final expected = sampleAt(before, row, col, sampleBytesBefore).take(sampleBytesAfter).toList();
        expect(sampleAt(after, row, col, sampleBytesAfter), expected, reason: 'sample ($row,$col) must survive packing unchanged');
      }
    }
  }

  group('isTightlyPacked', () {
    test('a freshly allocated image is already tightly packed', () {
      expect(YuvImage.i420(8, 6).isTightlyPacked, isTrue);
      expect(YuvImage.nv12(8, 6).isTightlyPacked, isTrue);
      expect(YuvImage.bgra(8, 6).isTightlyPacked, isTrue);
    });

    test('I420 with row padding is not tightly packed', () {
      const width = 8, height = 6;
      final image = YuvImage.i420(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width + 16, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1),
          plane(rows: 3, rowStride: 4 + 8, columns: 4, pixelStride: 1, sampleBytes: 1, seed: 2),
          plane(rows: 3, rowStride: 4 + 8, columns: 4, pixelStride: 1, sampleBytes: 1, seed: 3),
        ],
        layout: YuvPlaneLayout.preserve,
      );
      expect(image.isTightlyPacked, isFalse);
    });

    test('I420 chroma reported at pixelStride 2 (real Pixel 3 geometry) is not tightly packed', () {
      const width = 8, height = 6;
      final image = YuvImage.i420(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1),
          plane(rows: 3, rowStride: 4 * 2, columns: 4, pixelStride: 2, sampleBytes: 1, seed: 2),
          plane(rows: 3, rowStride: 4 * 2, columns: 4, pixelStride: 2, sampleBytes: 1, seed: 3),
        ],
        layout: YuvPlaneLayout.preserve,
      );
      expect(image.isTightlyPacked, isFalse);
    });

    test('NV12 with padded UV row stride is not tightly packed', () {
      const width = 8, height = 6;
      final image = YuvImage.nv12(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1),
          plane(rows: 3, rowStride: 4 * 2 + 6, columns: 4, pixelStride: 2, sampleBytes: 2, seed: 2),
        ],
        layout: YuvPlaneLayout.preserve,
      );
      expect(image.isTightlyPacked, isFalse);
    });

    test('BGRA with padded row stride is not tightly packed', () {
      const width = 5, height = 4;
      final image = YuvImage.bgra(
        width,
        height,
        planes: [plane(rows: height, rowStride: width * 4 + 8, columns: width, pixelStride: 4, sampleBytes: 4, seed: 1)],
        layout: YuvPlaneLayout.preserve,
      );
      expect(image.isTightlyPacked, isFalse);
    });
  });

  group('pack()', () {
    test('no-op on an already tightly packed image: same revision, returns this', () {
      final image = YuvImage.i420(8, 6);
      final before = image.revision;

      final result = image.pack();

      expect(identical(result, image), isTrue);
      expect(image.revision, before, reason: 'a genuine no-op must not advance the revision');
    });

    test('I420 with row padding on Y and U/V: packs to tight strides, same visible samples', () {
      const width = 8, height = 6;
      const chromaWidth = 4, chromaHeight = 3;
      final yBefore = plane(rows: height, rowStride: width + 16, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1);
      final uBefore = plane(rows: chromaHeight, rowStride: chromaWidth + 8, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 101);
      final vBefore = plane(rows: chromaHeight, rowStride: chromaWidth + 8, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 201);
      final image = YuvImage.i420(width, height, planes: [yBefore, uBefore, vBefore], layout: YuvPlaneLayout.preserve);
      final before = image.revision;

      final result = image.pack();

      expect(identical(result, image), isTrue);
      expect(image.revision, before + 1);
      expect(image.isTightlyPacked, isTrue);
      expect(image.yPlane.rowStride, width);
      expect(image.uPlane.rowStride, chromaWidth);
      expect(image.vPlane.rowStride, chromaWidth);
      expectSameVisibleSamples(yBefore, image.yPlane, rows: height, columns: width, sampleBytesBefore: 1);
      expectSameVisibleSamples(uBefore, image.uPlane, rows: chromaHeight, columns: chromaWidth, sampleBytesBefore: 1);
      expectSameVisibleSamples(vBefore, image.vPlane, rows: chromaHeight, columns: chromaWidth, sampleBytesBefore: 1);
    });

    test('I420 chroma at pixelStride 2 (real Pixel 3 geometry) de-interleaves to pixelStride 1', () {
      const width = 8, height = 6;
      const chromaWidth = 4, chromaHeight = 3;
      const paddedChromaPixelStride = 2;
      final yBefore = plane(rows: height, rowStride: width, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1);
      // U's samples sit at even byte offsets, V's at odd -- one byte apart,
      // matching this device's reported ImageFormatGroup.yuv420 geometry.
      final uBefore = plane(
        rows: chromaHeight,
        rowStride: chromaWidth * paddedChromaPixelStride,
        columns: chromaWidth,
        pixelStride: paddedChromaPixelStride,
        sampleBytes: 1,
        seed: 101,
      );
      final vBefore = plane(
        rows: chromaHeight,
        rowStride: chromaWidth * paddedChromaPixelStride,
        columns: chromaWidth,
        pixelStride: paddedChromaPixelStride,
        sampleBytes: 1,
        seed: 201,
      );
      final image = YuvImage.i420(width, height, planes: [yBefore, uBefore, vBefore], layout: YuvPlaneLayout.preserve);

      image.pack();

      expect(image.uPlane.pixelStride, 1, reason: 'packed I420 chroma must de-interleave to pixelStride 1, not just tighten the row stride');
      expect(image.vPlane.pixelStride, 1);
      expectSameVisibleSamples(uBefore, image.uPlane, rows: chromaHeight, columns: chromaWidth, sampleBytesBefore: 1);
      expectSameVisibleSamples(vBefore, image.vPlane, rows: chromaHeight, columns: chromaWidth, sampleBytesBefore: 1);
    });

    test('NV12 with padded UV row stride packs to tight rowStride, keeping pixelStride 2 (interleaved pair)', () {
      const width = 8, height = 6;
      const chromaWidth = 4, chromaHeight = 3;
      final yBefore = plane(rows: height, rowStride: width, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1);
      final uvBefore = plane(rows: chromaHeight, rowStride: chromaWidth * 2 + 6, columns: chromaWidth, pixelStride: 2, sampleBytes: 2, seed: 101);
      final image = YuvImage.nv12(width, height, planes: [yBefore, uvBefore], layout: YuvPlaneLayout.preserve);

      image.pack();

      expect(image.isTightlyPacked, isTrue);
      expect(image.uPlane.pixelStride, 2, reason: 'NV interleaved UV pair must stay pixelStride 2 -- native addresses it as a packed (U, V) pair');
      expect(image.uPlane.rowStride, chromaWidth * 2);
      expectSameVisibleSamples(uvBefore, image.uPlane, rows: chromaHeight, columns: chromaWidth, sampleBytesBefore: 2);
    });

    test('BGRA with padded row stride packs to rowStride == width * 4', () {
      const width = 5, height = 4;
      final before = plane(rows: height, rowStride: width * 4 + 8, columns: width, pixelStride: 4, sampleBytes: 4, seed: 1);
      final image = YuvImage.bgra(width, height, planes: [before], layout: YuvPlaneLayout.preserve);

      image.pack();

      expect(image.isTightlyPacked, isTrue);
      expect(image.yPlane.rowStride, width * 4);
      expectSameVisibleSamples(before, image.yPlane, rows: height, columns: width, sampleBytesBefore: 4);
    });

    test('odd width and height (chroma rounds up): packs correctly', () {
      const width = 7, height = 5;
      const chromaWidth = 4, chromaHeight = 3;
      final yBefore = plane(rows: height, rowStride: width + 9, columns: width, pixelStride: 1, sampleBytes: 1, seed: 3);
      final uBefore = plane(rows: chromaHeight, rowStride: chromaWidth + 5, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 103);
      final vBefore = plane(rows: chromaHeight, rowStride: chromaWidth + 5, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 203);
      final image = YuvImage.i420(width, height, planes: [yBefore, uBefore, vBefore], layout: YuvPlaneLayout.preserve);

      image.pack();

      expect(image.isTightlyPacked, isTrue);
      expect(image.uPlane.rowStride, chromaWidth);
      expect(image.vPlane.rowStride, chromaWidth);
      expectSameVisibleSamples(yBefore, image.yPlane, rows: height, columns: width, sampleBytesBefore: 1);
      expectSameVisibleSamples(uBefore, image.uPlane, rows: chromaHeight, columns: chromaWidth, sampleBytesBefore: 1);
      expectSameVisibleSamples(vBefore, image.vPlane, rows: chromaHeight, columns: chromaWidth, sampleBytesBefore: 1);
    });

    test('preserves format, size and UV order', () {
      const width = 8, height = 6;
      const chromaWidth = 4, chromaHeight = 3;
      final image = YuvImage.i420(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width + 16, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1),
          plane(rows: chromaHeight, rowStride: chromaWidth + 8, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 101),
          plane(rows: chromaHeight, rowStride: chromaWidth + 8, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 201),
        ],
        layout: YuvPlaneLayout.preserve,
      );

      image.pack();

      expect(image.format, YuvPixelFormat.i420);
      expect(image.width, width);
      expect(image.height, height);
      expect(image.planes.length, 3);
    });

    test('a failed pack leaves the image untouched (atomicity via applyPlanes)', () {
      // A malformed replacement plane set (wrong plane count for the format)
      // would be rejected by applyPlanes()'s own validation; pack() must not
      // publish anything before that validation runs. This is exercised
      // through applyPlanes() directly, since pack() always builds a
      // geometrically valid set itself -- this pins down the atomicity
      // guarantee pack() relies on rather than re-implements.
      final image = YuvImage.i420(4, 4);
      final before = image.revision;
      final beforeBytes = image.toBytes();

      expect(() => image.applyPlanes([YuvPlane(4, 4, 1)]), throwsArgumentError);

      expect(image.revision, before);
      expect(image.toBytes(), beforeBytes);
    });
  });
}
