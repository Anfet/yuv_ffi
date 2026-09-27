import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';

/// PACK-01D: `YuvImageToCameraExt.toInputImage()` must hand `google_mlkit_commons`
/// 0.11.0's Android byte-array path real NV21 bytes (`Y` then interleaved
/// **V, U** chroma) -- the only semi-planar layout it recognizes -- rather
/// than this package's UV-ordered `nv12` storage or three separate I420
/// planes mislabelled as `yuv420` (iOS-only in that enum, despite the name;
/// see its own doc comments). iOS gets a tight packed BGRA buffer.
///
/// Every case below builds its source planes with real row padding and/or a
/// pixel gap (`layout: YuvPlaneLayout.preserve`), so a fix that only works on
/// already-tight input would not be caught.
void main() {
  int deterministicByte(int seed, int index) => (index * 37 + seed) & 0xff;

  YuvPlane paddedPlane({
    required int rows,
    required int columns,
    required int pixelStride,
    required int sampleBytes,
    required int rowPadding,
    required int seed,
  }) {
    final rowStride = columns * pixelStride + rowPadding;
    final bytes = Uint8List(rows * rowStride);
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        for (var b = 0; b < sampleBytes; b++) {
          bytes[row * rowStride + col * pixelStride + b] = deterministicByte(seed + b, row * columns + col);
        }
      }
      for (var tail = columns * pixelStride; tail < rowStride; tail++) {
        bytes[row * rowStride + tail] = 0xEE;
      }
    }
    return YuvPlane(rows, rowStride, pixelStride, bytes);
  }

  test('I420 with padded/gapped planes produces true NV21 (Y then V,U) bytes', () {
    const width = 6;
    const height = 4;
    const chromaWidth = 3;
    const chromaHeight = 2;

    final yPlane = paddedPlane(rows: height, columns: width, pixelStride: 1, sampleBytes: 1, rowPadding: 5, seed: 1);
    final uPlane = paddedPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, rowPadding: 4, seed: 100);
    final vPlane = paddedPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, rowPadding: 4, seed: 200);

    final image = YuvImage.i420(width, height, planes: [yPlane, uPlane, vPlane], layout: YuvPlaneLayout.preserve);
    final inputImage = image.toInputImage();

    expect(inputImage.metadata!.format, InputImageFormat.nv21);
    expect(inputImage.metadata!.size, const Size(6, 4));

    final bytes = inputImage.bytes!;
    expect(bytes.length, width * height + chromaWidth * chromaHeight * 2);

    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        expect(bytes[row * width + col], deterministicByte(1, row * width + col), reason: 'Y[$row,$col]');
      }
    }

    final chromaStart = width * height;
    for (var row = 0; row < chromaHeight; row++) {
      for (var col = 0; col < chromaWidth; col++) {
        final i = row * chromaWidth + col;
        expect(bytes[chromaStart + i * 2], deterministicByte(200, i), reason: 'V[$row,$col] must come first (NV21)');
        expect(bytes[chromaStart + i * 2 + 1], deterministicByte(100, i), reason: 'U[$row,$col] must come second (NV21)');
      }
    }
  });

  test('NV12 (UV-ordered) with padded/gapped chroma is swapped to true NV21 (VU) bytes', () {
    const width = 6;
    const height = 4;
    const chromaWidth = 3;
    const chromaHeight = 2;

    final yPlane = paddedPlane(rows: height, columns: width, pixelStride: 1, sampleBytes: 1, rowPadding: 5, seed: 1);
    // Interleaved UV: sample seed 100 lands on the even (U) byte, 101 on the
    // odd (V) byte of each pair -- deterministicByte's `seed + b` for b in 0..1.
    final uvPlane = paddedPlane(rows: chromaHeight, columns: chromaWidth, pixelStride: 2, sampleBytes: 2, rowPadding: 6, seed: 100);

    final image = YuvImage.nv12(width, height, planes: [yPlane, uvPlane], layout: YuvPlaneLayout.preserve);
    final inputImage = image.toInputImage();

    expect(inputImage.metadata!.format, InputImageFormat.nv21);

    final bytes = inputImage.bytes!;
    final chromaStart = width * height;
    for (var row = 0; row < chromaHeight; row++) {
      for (var col = 0; col < chromaWidth; col++) {
        final i = row * chromaWidth + col;
        final sourceU = deterministicByte(100, i);
        final sourceV = deterministicByte(101, i);
        expect(bytes[chromaStart + i * 2], sourceV, reason: 'V[$row,$col] must be written first (NV21)');
        expect(bytes[chromaStart + i * 2 + 1], sourceU, reason: 'U[$row,$col] must be written second (NV21)');
      }
    }
  });

  test('BGRA with a padded plane produces a tight buffer with bytesPerRow == width * 4', () {
    const width = 5;
    const height = 3;
    final bgraPlane = paddedPlane(rows: height, columns: width, pixelStride: 4, sampleBytes: 4, rowPadding: 8, seed: 1);

    final image = YuvImage.bgra(width, height, planes: [bgraPlane], layout: YuvPlaneLayout.preserve);
    final inputImage = image.toInputImage();

    expect(inputImage.metadata!.format, InputImageFormat.bgra8888);
    expect(inputImage.metadata!.bytesPerRow, width * 4);

    final bytes = inputImage.bytes!;
    expect(bytes.length, width * height * 4);
    for (var row = 0; row < height; row++) {
      for (var col = 0; col < width; col++) {
        for (var b = 0; b < 4; b++) {
          expect(bytes[row * width * 4 + col * 4 + b], deterministicByte(1 + b, row * width + col), reason: 'BGRA[$row,$col,$b]');
        }
      }
    }
  });
}
