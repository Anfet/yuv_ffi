import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';
import 'package:yuv_ffi_example/ext.dart';

/// Camera plane imports are tightly packed while preserving every visible
/// sample, including gapped I420 chroma and padded source rows.
void main() {
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

  /// Verifies that importing camera planes drops only row and pixel gaps.
  void expectSameVisibleSamples(
    CameraImageData data, {
    required List<int> planeRows,
    required List<int> planeColumns,
    required List<int> planeSourcePixelStrides,
    List<int>? planeSampleBytes,
  }) {
    final sampleBytes = planeSampleBytes ?? planeSourcePixelStrides;
    final packed = buildFromCameraData(data);
    expect(packed.planes, hasLength(data.planes.length));
    for (var i = 0; i < packed.planes.length; i++) {
      final rows = planeRows[i];
      final columns = planeColumns[i];
      final source = data.planes[i];
      final sourcePixelStride = planeSourcePixelStrides[i];
      final destPixelStride = sampleBytes[i];
      expect(packed.planes[i].bytesPerRow, columns * destPixelStride);
      expect(packed.planes[i].pixelStride, destPixelStride);
      for (var row = 0; row < rows; row++) {
        for (var col = 0; col < columns; col++) {
          for (var b = 0; b < destPixelStride; b++) {
            final sourceByte = source.bytes[row * source.bytesPerRow + col * sourcePixelStride + b];
            final packedByte = packed.planes[i].bytes[row * packed.planes[i].bytesPerRow + col * destPixelStride + b];
            expect(packedByte, sourceByte, reason: 'plane $i row $row col $col byte $b differs from the visible camera sample');
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
        planeSourcePixelStrides: [1, 1, 1],
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
        planeSourcePixelStrides: [1, 1, 1],
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
        planeSourcePixelStrides: [1, 1, 1],
      );
    });

    test('separate U/V planes reported with bytesPerPixel 2, matching a real Pixel 3 camera frame', () {
      // Some Android devices label `ImageFormatGroup.yuv420` frames with two
      // separate `Image.Plane`s for U and V, yet each plane's
      // `bytesPerPixel` is 2, not 1 -- the same physically interleaved
      // chroma buffer NV12/NV21 uses, split a single byte apart into "U" and
      // "V" views instead of the fully planar layout the format name
      // suggests. A tight import that merely drops row padding but keeps
      // this pixel stride would leave every other byte belonging to the
      // *other* channel inside what should be a pure U or V plane -- this
      // proves the packed import actually de-interleaves down to
      // pixelStride 1, not just tightens the row stride.
      const width = 8;
      const height = 6;
      const yRowStride = width + 16;
      const chromaWidth = (width + 1) ~/ 2;
      const chromaHeight = (height + 1) ~/ 2;
      const chromaPixelStride = 2;
      const chromaRowStride = chromaWidth * chromaPixelStride + 8; // gapped, interleaved-width stride

      final yBytes = paddedPlaneBytes(rows: height, rowStride: yRowStride, columns: width, pixelStride: 1, sampleBytes: 1, seed: 1);
      // U's samples sit at even byte offsets, V's at odd -- one byte apart,
      // as the plugin reports them on this class of device.
      final uBytes = paddedPlaneBytes(
        rows: chromaHeight,
        rowStride: chromaRowStride,
        columns: chromaWidth,
        pixelStride: chromaPixelStride,
        sampleBytes: 1,
        seed: 101,
      );
      final vBytes = paddedPlaneBytes(
        rows: chromaHeight,
        rowStride: chromaRowStride,
        columns: chromaWidth,
        pixelStride: chromaPixelStride,
        sampleBytes: 1,
        seed: 201,
      );

      final data = CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 'YUV420'),
        width: width,
        height: height,
        planes: [
          CameraImagePlane(bytes: yBytes, bytesPerRow: yRowStride, bytesPerPixel: 1, width: width, height: height),
          CameraImagePlane(bytes: uBytes, bytesPerRow: chromaRowStride, bytesPerPixel: chromaPixelStride, width: chromaWidth, height: chromaHeight),
          CameraImagePlane(bytes: vBytes, bytesPerRow: chromaRowStride, bytesPerPixel: chromaPixelStride, width: chromaWidth, height: chromaHeight),
        ],
      );

      expectSameVisibleSamples(
        data,
        planeRows: [height, chromaHeight, chromaHeight],
        planeColumns: [width, chromaWidth, chromaWidth],
        planeSourcePixelStrides: [1, chromaPixelStride, chromaPixelStride],
        planeSampleBytes: const [1, 1, 1],
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

      expectSameVisibleSamples(data, planeRows: [height, chromaHeight], planeColumns: [width, chromaWidth], planeSourcePixelStrides: [1, 2]);
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

      expectSameVisibleSamples(data, planeRows: [height, chromaHeight], planeColumns: [width, chromaWidth], planeSourcePixelStrides: [1, 2]);
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

      expectSameVisibleSamples(data, planeRows: [height], planeColumns: [width], planeSourcePixelStrides: [4]);
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

      expectSameVisibleSamples(data, planeRows: [height], planeColumns: [width], planeSourcePixelStrides: [4]);
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
