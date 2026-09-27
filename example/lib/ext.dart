import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// PACK-00 experiment switch only: when `true`, [CameraImageExt.toYuvImage]
/// copies each plane into a tightly packed buffer (no row padding) instead of
/// preserving the camera's reported `bytesPerRow`. Defaults to `false` (the
/// existing padded-preserving behavior) until PACK-00's measurement and
/// independent review decide whether packing belongs in the public contract;
/// flipping it does not change `YuvImage`'s constructor or native code.
bool kYuvCameraPreviewPackPlanes = false;

extension CameraImageExt on CameraImage {
  YuvImage toYuvImage() {
    // Only the first plane spans the full image height; chroma planes of
    // planar/semi-planar formats hold ceil(height / 2) rows. Camera buffers
    // may omit the unused padding after their last row, while YuvPlane stores
    // a complete `rows * bytesPerRow` layout.
    final isPacked = format.group == ImageFormatGroup.bgra8888;
    final chromaRows = (height + 1) ~/ 2;
    final chromaColumns = (width + 1) ~/ 2;

    final planes = <YuvPlane>[];
    for (int i = 0; i < this.planes.length; i++) {
      final p = this.planes[i];
      final rows = (isPacked || i == 0) ? height : chromaRows;
      final columns = (isPacked || i == 0) ? width : chromaColumns;
      // iOS camera frames are packed BGRA8888. `CameraPlane.bytesPerPixel`
      // is not reliable there, while the native ABI requires the actual
      // four-byte packed-pixel stride.
      final pixelStride = isPacked ? 4 : p.bytesPerPixel ?? 1;
      final sampleBytes = isPacked
          ? pixelStride
          : format.group == ImageFormatGroup.nv21 && i > 0
          ? pixelStride
          : 1;
      final sourceRowStride = p.bytesPerRow;
      final minimumLength = (rows - 1) * sourceRowStride + (columns - 1) * pixelStride + sampleBytes;
      if (p.bytes.length < minimumLength) {
        throw FormatException('Camera plane $i is truncated: expected at least $minimumLength bytes, got ${p.bytes.length}');
      }

      if (kYuvCameraPreviewPackPlanes) {
        planes.add(
          _packPlane(
            source: p.bytes,
            rows: rows,
            columns: columns,
            sourceRowStride: sourceRowStride,
            pixelStride: pixelStride,
            sampleBytes: sampleBytes,
          ),
        );
      } else {
        final expectedLength = rows * sourceRowStride;
        final bytes = Uint8List(expectedLength);
        final copyLength = p.bytes.length < expectedLength ? p.bytes.length : expectedLength;
        bytes.setRange(0, copyLength, p.bytes);
        planes.add(YuvPlane(rows, sourceRowStride, pixelStride, bytes));
      }
    }

    switch (format.group) {
      case ImageFormatGroup.yuv420:
        return YuvImage.i420(width, height, planes: planes);

      case ImageFormatGroup.nv21:
        // The deprecated nv21 constructor is an alias for the same UV-ordered
        // storage as nv12; both preserve these camera bytes as supplied.
        // ignore: deprecated_member_use
        return YuvImage.nv21(width, height, planes: planes);
      case ImageFormatGroup.bgra8888:
        return YuvImage.bgra(width, height, planes: planes);
      case ImageFormatGroup.unknown:
      case ImageFormatGroup.jpeg:
        throw FormatException('Unsupported format for CameraImage to YuvImage; ${format.group}');
    }
  }
}

/// Copies [rows] * [columns] visible samples of one plane out of [source],
/// which is laid out with [sourceRowStride] bytes per row and [pixelStride]
/// bytes between neighboring samples, into a new [YuvPlane] with row stride
/// `columns * pixelStride` -- i.e. no row padding and no inter-sample gap.
///
/// [sampleBytes] is how many leading bytes of each [pixelStride]-wide slot are
/// copied (1 for planar Y/U/V, [pixelStride] itself for interleaved NV12/NV21
/// UV pairs and packed BGRA8888), so trailing gap bytes inside a pixel slot
/// (there are none in the formats this project stores, but the copy stays
/// correct if one is ever added) are never carried into the tight output.
YuvPlane _packPlane({
  required Uint8List source,
  required int rows,
  required int columns,
  required int sourceRowStride,
  required int pixelStride,
  required int sampleBytes,
}) {
  final tightRowStride = columns * pixelStride;
  final packed = Uint8List(rows * tightRowStride);
  for (var row = 0; row < rows; row++) {
    final sourceRowStart = row * sourceRowStride;
    final destRowStart = row * tightRowStride;
    if (sampleBytes == pixelStride) {
      packed.setRange(destRowStart, destRowStart + tightRowStride, source, sourceRowStart);
      continue;
    }
    for (var col = 0; col < columns; col++) {
      packed[destRowStart + col * pixelStride] = source[sourceRowStart + col * pixelStride];
    }
  }
  return YuvPlane(rows, tightRowStride, pixelStride, packed);
}

extension YuvImageToCameraExt on YuvImage {
  InputImage toInputImage() {
    InputImageFormat format;
    switch (this.format) {
      case YuvPixelFormat.i420:
        format = InputImageFormat.yuv420;
        break;
      case YuvPixelFormat.nv12:
        format = InputImageFormat.nv21;
        break;
      case YuvPixelFormat.bgra8888:
        format = InputImageFormat.bgra8888;
        break;
    }

    final meta = InputImageMetadata(size: size, rotation: InputImageRotation.rotation0deg, format: format, bytesPerRow: planes.first.bytesPerRow);

    return InputImage.fromBytes(bytes: toBytes(), metadata: meta);
  }
}
