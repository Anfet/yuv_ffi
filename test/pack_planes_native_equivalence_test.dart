import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/loader/loader.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// PACK-00: the packed-vs-padded plane comparison in `example/test/
/// camera_image_pack_planes_test.dart` only proves the two imports copy the
/// same visible sample bytes -- it cannot call native operations in that
/// project's own `flutter test` run because `yuv_ffi`'s dynamic library is
/// not next to that test binary. This file completes the comparison: it
/// builds the same padded-vs-tight [YuvPlane] pairs directly (no `camera`
/// dependency needed) and asserts [YuvImage.toBgraBytes] and
/// [YuvImage.applyRotation] produce byte-identical output for both, for I420
/// (gapped U/V), NV12 (interleaved UV) and BGRA8888, including odd
/// width/height. Equal output after equal-but-differently-laid-out input is
/// the correctness precondition PACK-00's raw-data report builds its speed
/// comparison on.
void main() {
  final bool nativeAvailable = _checkNativeAvailable();

  int deterministicByte(int seed, int index) => (index * 37 + seed) & 0xff;

  /// A plane holding [rows] * [columns] visible samples of [sampleBytes] each,
  /// spaced [pixelStride] bytes apart, at [rowStride] bytes per row --
  /// [rowStride] may exceed `columns * pixelStride` (row padding).
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

  /// Same visible content as [plane], but with `rowStride == columns * pixelStride`
  /// (no row padding) -- what PACK-00's packing import produces.
  YuvPlane tightPlane({required int rows, required int columns, required int pixelStride, required int sampleBytes, required int seed}) =>
      plane(rows: rows, rowStride: columns * pixelStride, columns: columns, pixelStride: pixelStride, sampleBytes: sampleBytes, seed: seed);

  void expectSameNativeOutput(YuvImage padded, YuvImage packed) {
    expect(packed.toBgraBytes(), padded.toBgraBytes(), reason: 'toBgraBytes() must agree between padded and packed import');

    if (padded.format == YuvPixelFormat.bgra8888) return;
    final rotatedPadded = padded.copy().applyRotation(YuvImageRotation.rotation90);
    final rotatedPacked = packed.copy().applyRotation(YuvImageRotation.rotation90);
    expect(rotatedPacked.toBgraBytes(), rotatedPadded.toBgraBytes(), reason: 'applyRotation() result must agree between padded and packed import');
  }

  group('padded vs. packed YuvPlane produce identical native output', () {
    setUpAll(() async => YuvFfi.initialize());

    test('I420, even geometry, gapped Y and U/V stride', () {
      const width = 8;
      const height = 6;
      const chromaWidth = (width + 1) ~/ 2;
      const chromaHeight = (height + 1) ~/ 2;

      final padded = YuvImage.i420(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width + 16, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1),
          plane(rows: chromaHeight, rowStride: chromaWidth + 8, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 101),
          plane(rows: chromaHeight, rowStride: chromaWidth + 8, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 201),
        ],
      );
      final packed = YuvImage.i420(
        width,
        height,
        planes: [
          tightPlane(rows: height, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1),
          tightPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 101),
          tightPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 201),
        ],
      );

      expectSameNativeOutput(padded, packed);
    });

    test('I420, odd width and height (chroma rounds up)', () {
      const width = 7;
      const height = 5;
      const chromaWidth = (width + 1) ~/ 2;
      const chromaHeight = (height + 1) ~/ 2;

      final padded = YuvImage.i420(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width + 9, columns: width, pixelStride: 1, sampleBytes: 1, seed: 3),
          plane(rows: chromaHeight, rowStride: chromaWidth + 5, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 103),
          plane(rows: chromaHeight, rowStride: chromaWidth + 5, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 203),
        ],
      );
      final packed = YuvImage.i420(
        width,
        height,
        planes: [
          tightPlane(rows: height, columns: width, pixelStride: 1, sampleBytes: 1, seed: 3),
          tightPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 103),
          tightPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 203),
        ],
      );

      expectSameNativeOutput(padded, packed);
    });

    test('NV12, even geometry, gapped Y and UV stride', () {
      const width = 8;
      const height = 6;
      const chromaWidth = (width + 1) ~/ 2;
      const chromaHeight = (height + 1) ~/ 2;

      final padded = YuvImage.nv12(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width + 12, columns: width, pixelStride: 1, sampleBytes: 1, seed: 7),
          plane(rows: chromaHeight, rowStride: chromaWidth * 2 + 6, columns: chromaWidth, pixelStride: 2, sampleBytes: 2, seed: 107),
        ],
      );
      final packed = YuvImage.nv12(
        width,
        height,
        planes: [
          tightPlane(rows: height, columns: width, pixelStride: 1, sampleBytes: 1, seed: 7),
          tightPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 2, sampleBytes: 2, seed: 107),
        ],
      );

      expectSameNativeOutput(padded, packed);
    });

    test('NV12, odd width and height', () {
      const width = 9;
      const height = 7;
      const chromaWidth = (width + 1) ~/ 2;
      const chromaHeight = (height + 1) ~/ 2;

      final padded = YuvImage.nv12(
        width,
        height,
        planes: [
          plane(rows: height, rowStride: width + 7, columns: width, pixelStride: 1, sampleBytes: 1, seed: 9),
          plane(rows: chromaHeight, rowStride: chromaWidth * 2 + 4, columns: chromaWidth, pixelStride: 2, sampleBytes: 2, seed: 109),
        ],
      );
      final packed = YuvImage.nv12(
        width,
        height,
        planes: [
          tightPlane(rows: height, columns: width, pixelStride: 1, sampleBytes: 1, seed: 9),
          tightPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 2, sampleBytes: 2, seed: 109),
        ],
      );

      expectSameNativeOutput(padded, packed);
    });

    test('BGRA8888, padded row stride, even geometry', () {
      const width = 5;
      const height = 4;

      final padded = YuvImage.bgra(
        width,
        height,
        planes: [plane(rows: height, rowStride: width * 4 + 8, columns: width, pixelStride: 4, sampleBytes: 4, seed: 11)],
      );
      final packed = YuvImage.bgra(
        width,
        height,
        planes: [tightPlane(rows: height, columns: width, pixelStride: 4, sampleBytes: 4, seed: 11)],
      );

      expectSameNativeOutput(padded, packed);
    });

    test('BGRA8888, padded row stride, odd width', () {
      const width = 7;
      const height = 3;

      final padded = YuvImage.bgra(
        width,
        height,
        planes: [plane(rows: height, rowStride: width * 4 + 12, columns: width, pixelStride: 4, sampleBytes: 4, seed: 13)],
      );
      final packed = YuvImage.bgra(
        width,
        height,
        planes: [tightPlane(rows: height, columns: width, pixelStride: 4, sampleBytes: 4, seed: 13)],
      );

      expectSameNativeOutput(padded, packed);
    });
  }, skip: nativeAvailable ? false : 'native yuv_ffi library is not available on this host');
}

bool _checkNativeAvailable() {
  try {
    library;
    return true;
  } catch (_) {
    return false;
  }
}
