import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';

/// PACK-00: [kYuvCameraPreviewPackPlanes] switches [CameraImageExt.toYuvImage]
/// between preserving the camera's padded `bytesPerRow` (the existing,
/// default behavior, covered by `camera_image_to_yuv_image_padding_test.dart`)
/// and copying only the visible samples into a tight buffer. This file proves
/// the two paths agree on every visible sample they import, for the plane
/// shapes the experiment cares about: I420 with a gapped U/V stride, NV12
/// (interleaved UV), BGRA8888, odd width/height (chroma rounds up), and a
/// source buffer that omits the padding after its last row.
///
/// The derived [YuvImage.toBgraBytes] / [YuvImage.applyRotation] agreement is
/// exercised separately, in the root package's
/// `test/pack_planes_native_equivalence_test.dart`: that runs where the
/// native `yuv_ffi` library and `YuvFfi.initialize()` are already the
/// established convention for a native-backed test, and this example project
/// has no `camera`-free way to build the same padded/packed [YuvPlane] pairs
/// without going through [CameraImage], so duplicating that native comparison
/// here would only add a second, less-established way to gate on native
/// availability.
void main() {
  setUp(() => kYuvCameraPreviewPackPlanes = false);
  tearDown(() => kYuvCameraPreviewPackPlanes = false);

  int deterministicByte(int seed, int index) => (index * 37 + seed) & 0xff;

  Uint8List paddedPlaneBytes({
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
      // Sentinel padding tail: a bug that reads past the declared sample
      // width would surface as an unexpected value, not a zero.
      for (var col = columns * pixelStride; col < rowStride; col++) {
        bytes[row * rowStride + col] = 0xEE;
      }
    }
    return bytes;
  }

  YuvImage buildFromCameraData(CameraImageData data) => CameraImage.fromPlatformInterface(data).toYuvImage();

  /// Builds the same [CameraImageData] once, then converts it with
  /// [kYuvCameraPreviewPackPlanes] both off and on, asserting every visible
  /// sample of every plane is byte-identical between the two -- packing must
  /// only drop padding, never reorder or corrupt a sample.
  void expectSameVisibleSamples(
    CameraImageData data, {
    required List<int> planeRows,
    required List<int> planeColumns,
    required List<int> planePixelStrides,
  }) {
    kYuvCameraPreviewPackPlanes = false;
    final padded = buildFromCameraData(data);
    kYuvCameraPreviewPackPlanes = true;
    final packed = buildFromCameraData(data);

    expect(packed.planes, hasLength(padded.planes.length));
    for (var i = 0; i < padded.planes.length; i++) {
      final rows = planeRows[i];
      final columns = planeColumns[i];
      final pixelStride = planePixelStrides[i];
      expect(packed.planes[i].bytesPerRow, columns * pixelStride, reason: 'plane $i: packed row stride must equal columns * pixelStride');
      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < columns; col++) {
          for (var b = 0; b < pixelStride; b++) {
            final paddedByte = padded.planes[i].bytes[row * padded.planes[i].bytesPerRow + col * pixelStride + b];
            final packedByte = packed.planes[i].bytes[row * packed.planes[i].bytesPerRow + col * pixelStride + b];
            expect(packedByte, paddedByte, reason: 'plane $i row $row col $col byte $b differs between padded and packed import');
          }
        }
      }
    }
  }

  group('I420 with gapped U/V stride', () {
    test('even 720x480-like geometry', () {
      const width = 8;
      const height = 6;
      const yRowStride = width + 16; // padded, mirrors the Pixel 3 720x480 case proportionally
      const chromaWidth = (width + 1) ~/ 2;
      const chromaHeight = (height + 1) ~/ 2;
      const chromaRowStride = chromaWidth + 8; // gapped U/V stride

      final yBytes = paddedPlaneBytes(rows: height, rowStride: yRowStride, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1);
      final uBytes = paddedPlaneBytes(
        rows: chromaHeight,
        rowStride: chromaRowStride,
        columns: chromaWidth,
        pixelStride: 1,
        sampleBytes: 1,
        seed: 101,
      );
      final vBytes = paddedPlaneBytes(
        rows: chromaHeight,
        rowStride: chromaRowStride,
        columns: chromaWidth,
        pixelStride: 1,
        sampleBytes: 1,
        seed: 201,
      );

      final data = CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 'YUV420'),
        width: width,
        height: height,
        planes: [
          CameraImagePlane(bytes: yBytes, bytesPerRow: yRowStride, bytesPerPixel: 1, width: width, height: height),
          CameraImagePlane(bytes: uBytes, bytesPerRow: chromaRowStride, bytesPerPixel: 1, width: chromaWidth, height: chromaHeight),
          CameraImagePlane(bytes: vBytes, bytesPerRow: chromaRowStride, bytesPerPixel: 1, width: chromaWidth, height: chromaHeight),
        ],
      );

      expectSameVisibleSamples(
        data,
        planeRows: [height, chromaHeight, chromaHeight],
        planeColumns: [width, chromaWidth, chromaWidth],
        planePixelStrides: [1, 1, 1],
      );
    });

    test('odd width and height (chroma rounds up)', () {
      const width = 7;
      const height = 5;
      const yRowStride = width + 9;
      const chromaWidth = (width + 1) ~/ 2; // 4
      const chromaHeight = (height + 1) ~/ 2; // 3
      const chromaRowStride = chromaWidth + 5;

      final yBytes = paddedPlaneBytes(rows: height, rowStride: yRowStride, columns: width, pixelStride: 1, sampleBytes: 1, seed: 3);
      final uBytes = paddedPlaneBytes(
        rows: chromaHeight,
        rowStride: chromaRowStride,
        columns: chromaWidth,
        pixelStride: 1,
        sampleBytes: 1,
        seed: 103,
      );
      final vBytes = paddedPlaneBytes(
        rows: chromaHeight,
        rowStride: chromaRowStride,
        columns: chromaWidth,
        pixelStride: 1,
        sampleBytes: 1,
        seed: 203,
      );

      final data = CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 'YUV420'),
        width: width,
        height: height,
        planes: [
          CameraImagePlane(bytes: yBytes, bytesPerRow: yRowStride, bytesPerPixel: 1, width: width, height: height),
          CameraImagePlane(bytes: uBytes, bytesPerRow: chromaRowStride, bytesPerPixel: 1, width: chromaWidth, height: chromaHeight),
          CameraImagePlane(bytes: vBytes, bytesPerRow: chromaRowStride, bytesPerPixel: 1, width: chromaWidth, height: chromaHeight),
        ],
      );

      expectSameVisibleSamples(
        data,
        planeRows: [height, chromaHeight, chromaHeight],
        planeColumns: [width, chromaWidth, chromaWidth],
        planePixelStrides: [1, 1, 1],
      );
    });

    test('source omits padding after the last row', () {
      const width = 6;
      const height = 4;
      const yRowStride = width + 10;
      const chromaWidth = (width + 1) ~/ 2;
      const chromaHeight = (height + 1) ~/ 2;
      const chromaRowStride = chromaWidth + 6;

      final fullY = paddedPlaneBytes(rows: height, rowStride: yRowStride, columns: width, pixelStride: 1, sampleBytes: 1, seed: 5);
      final fullU = paddedPlaneBytes(rows: chromaHeight, rowStride: chromaRowStride, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 105);
      final fullV = paddedPlaneBytes(rows: chromaHeight, rowStride: chromaRowStride, columns: chromaWidth, pixelStride: 1, sampleBytes: 1, seed: 205);

      // Truncate each plane to the minimum length: full rows up to the last
      // one, then only the last row's visible columns, no trailing padding.
      Uint8List truncateLastRow(Uint8List full, int rows, int rowStride, int columns, int pixelStride) {
        final minimumLength = (rows - 1) * rowStride + columns * pixelStride;
        return Uint8List.sublistView(full, 0, minimumLength);
      }

      final yBytes = truncateLastRow(fullY, height, yRowStride, width, 1);
      final uBytes = truncateLastRow(fullU, chromaHeight, chromaRowStride, chromaWidth, 1);
      final vBytes = truncateLastRow(fullV, chromaHeight, chromaRowStride, chromaWidth, 1);

      final data = CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 'YUV420'),
        width: width,
        height: height,
        planes: [
          CameraImagePlane(bytes: yBytes, bytesPerRow: yRowStride, bytesPerPixel: 1, width: width, height: height),
          CameraImagePlane(bytes: uBytes, bytesPerRow: chromaRowStride, bytesPerPixel: 1, width: chromaWidth, height: chromaHeight),
          CameraImagePlane(bytes: vBytes, bytesPerRow: chromaRowStride, bytesPerPixel: 1, width: chromaWidth, height: chromaHeight),
        ],
      );

      expectSameVisibleSamples(
        data,
        planeRows: [height, chromaHeight, chromaHeight],
        planeColumns: [width, chromaWidth, chromaWidth],
        planePixelStrides: [1, 1, 1],
      );
    });
  });

  group('NV12/NV21 interleaved UV', () {
    test('even geometry with gapped UV stride', () {
      const width = 8;
      const height = 6;
      const yRowStride = width + 12;
      const chromaWidth = (width + 1) ~/ 2;
      const chromaHeight = (height + 1) ~/ 2;
      const uvRowStride = chromaWidth * 2 + 6; // gapped interleaved UV stride

      final yBytes = paddedPlaneBytes(rows: height, rowStride: yRowStride, columns: width, pixelStride: 1, sampleBytes: 1, seed: 7);
      final uvBytes = paddedPlaneBytes(rows: chromaHeight, rowStride: uvRowStride, columns: chromaWidth, pixelStride: 2, sampleBytes: 2, seed: 107);

      final data = CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 'NV21'),
        width: width,
        height: height,
        planes: [
          CameraImagePlane(bytes: yBytes, bytesPerRow: yRowStride, bytesPerPixel: 1, width: width, height: height),
          CameraImagePlane(bytes: uvBytes, bytesPerRow: uvRowStride, bytesPerPixel: 2, width: chromaWidth, height: chromaHeight),
        ],
      );

      expectSameVisibleSamples(data, planeRows: [height, chromaHeight], planeColumns: [width, chromaWidth], planePixelStrides: [1, 2]);
    });

    test('odd width and height', () {
      const width = 9;
      const height = 7;
      const yRowStride = width + 7;
      const chromaWidth = (width + 1) ~/ 2; // 5
      const chromaHeight = (height + 1) ~/ 2; // 4
      const uvRowStride = chromaWidth * 2 + 4;

      final yBytes = paddedPlaneBytes(rows: height, rowStride: yRowStride, columns: width, pixelStride: 1, sampleBytes: 1, seed: 9);
      final uvBytes = paddedPlaneBytes(rows: chromaHeight, rowStride: uvRowStride, columns: chromaWidth, pixelStride: 2, sampleBytes: 2, seed: 109);

      final data = CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 'NV21'),
        width: width,
        height: height,
        planes: [
          CameraImagePlane(bytes: yBytes, bytesPerRow: yRowStride, bytesPerPixel: 1, width: width, height: height),
          CameraImagePlane(bytes: uvBytes, bytesPerRow: uvRowStride, bytesPerPixel: 2, width: chromaWidth, height: chromaHeight),
        ],
      );

      expectSameVisibleSamples(data, planeRows: [height, chromaHeight], planeColumns: [width, chromaWidth], planePixelStrides: [1, 2]);
    });
  });

  group('BGRA8888 packed pixels', () {
    test('padded row stride, even geometry', () {
      const width = 5;
      const height = 4;
      const rowStride = width * 4 + 8;

      final bytes = paddedPlaneBytes(rows: height, rowStride: rowStride, columns: width, pixelStride: 4, sampleBytes: 4, seed: 11);

      final data = CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 'BGRA'),
        width: width,
        height: height,
        planes: [CameraImagePlane(bytes: bytes, bytesPerRow: rowStride, bytesPerPixel: 4, width: width, height: height)],
      );

      expectSameVisibleSamples(data, planeRows: [height], planeColumns: [width], planePixelStrides: [4]);
    });

    test('padded row stride, odd width', () {
      const width = 7;
      const height = 3;
      const rowStride = width * 4 + 12;

      final bytes = paddedPlaneBytes(rows: height, rowStride: rowStride, columns: width, pixelStride: 4, sampleBytes: 4, seed: 13);

      final data = CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 'BGRA'),
        width: width,
        height: height,
        planes: [CameraImagePlane(bytes: bytes, bytesPerRow: rowStride, bytesPerPixel: 4, width: width, height: height)],
      );

      expectSameVisibleSamples(data, planeRows: [height], planeColumns: [width], planePixelStrides: [4]);
    });
  });

  group('toInputImage() metadata after packing', () {
    test('bytesPerRow reflects the tight stride, not the camera padded one', () {
      const width = 8;
      const height = 6;
      const yRowStride = width + 16;
      final yBytes = paddedPlaneBytes(rows: height, rowStride: yRowStride, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1);
      final chromaWidth = (width + 1) ~/ 2;
      final chromaHeight = (height + 1) ~/ 2;
      const chromaRowStride = 4 + 8;
      final uBytes = paddedPlaneBytes(
        rows: chromaHeight,
        rowStride: chromaRowStride,
        columns: chromaWidth,
        pixelStride: 1,
        sampleBytes: 1,
        seed: 101,
      );
      final vBytes = paddedPlaneBytes(
        rows: chromaHeight,
        rowStride: chromaRowStride,
        columns: chromaWidth,
        pixelStride: 1,
        sampleBytes: 1,
        seed: 201,
      );

      final data = CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 'YUV420'),
        width: width,
        height: height,
        planes: [
          CameraImagePlane(bytes: yBytes, bytesPerRow: yRowStride, bytesPerPixel: 1, width: width, height: height),
          CameraImagePlane(bytes: uBytes, bytesPerRow: chromaRowStride, bytesPerPixel: 1, width: chromaWidth, height: chromaHeight),
          CameraImagePlane(bytes: vBytes, bytesPerRow: chromaRowStride, bytesPerPixel: 1, width: chromaWidth, height: chromaHeight),
        ],
      );

      kYuvCameraPreviewPackPlanes = true;
      final packed = buildFromCameraData(data);
      final inputImage = packed.toInputImage();

      expect(
        inputImage.metadata?.bytesPerRow,
        width,
        reason: 'a packed Y plane has no row padding: bytesPerRow must equal width, not the camera stride',
      );
      expect(
        inputImage.bytes?.length,
        packed.toBytes().length,
        reason: 'toInputImage() bytes must be the packed image\'s own tight toBytes() output',
      );
    });
  });
}
