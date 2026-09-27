import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// PACK-01C: when `true` (the default), [CameraImageExt.toYuvImage] copies
/// each plane into a tightly packed buffer (no row padding, and -- for I420
/// chroma reported at `pixelStride == 2` -- no per-sample pixel gap) instead
/// of preserving the camera's reported `bytesPerRow`. PACK-00 measured this at
/// 3.3x faster `applyRotation` and +23% shown FPS on a real Pixel 3 in a
/// release build, which is why the normal mobile preview now imports densely
/// by default. Set to `false` to reproduce the previous padded-preserving
/// import, e.g. for the padded/packed A/B comparison in
/// `Pack00BenchScreen`/PACK-00's device tests. Flipping it does not change
/// `YuvImage`'s constructor or native code -- both variants are built here in
/// `_packPlane`/the padded branch below, then handed to the factory with
/// `layout: YuvPlaneLayout.preserve` so the factory's own packing default
/// never runs a second time over either one.
bool kYuvCameraPreviewPackPlanes = true;

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
            sourcePixelStride: pixelStride,
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

    // This method already decides packed vs. padded above (kYuvCameraPreviewPackPlanes),
    // byte-for-byte; PACK-01B's factory default would otherwise silently
    // repack the padded branch a second time; here layout is always
    // `.preserve` regardless of that default.
    switch (format.group) {
      case ImageFormatGroup.yuv420:
        return YuvImage.i420(width, height, planes: planes, layout: YuvPlaneLayout.preserve);

      case ImageFormatGroup.nv21:
        // The deprecated nv21 constructor is an alias for the same UV-ordered
        // storage as nv12; both preserve these camera bytes as supplied.
        // ignore: deprecated_member_use
        return YuvImage.nv21(width, height, planes: planes, layout: YuvPlaneLayout.preserve);
      case ImageFormatGroup.bgra8888:
        return YuvImage.bgra(width, height, planes: planes, layout: YuvPlaneLayout.preserve);
      case ImageFormatGroup.unknown:
      case ImageFormatGroup.jpeg:
        throw FormatException('Unsupported format for CameraImage to YuvImage; ${format.group}');
    }
  }
}

/// Copies [rows] * [columns] visible samples of one plane out of [source],
/// which is laid out with [sourceRowStride] bytes per row and
/// [sourcePixelStride] bytes between neighboring samples, into a new
/// [YuvPlane] with **no row padding and no inter-sample gap**: row stride
/// `columns * sampleBytes` and pixel stride `sampleBytes`.
///
/// [sampleBytes] is how many leading bytes of each [sourcePixelStride]-wide
/// source slot are copied (1 for a planar Y/U/V sample, [sourcePixelStride]
/// itself for an interleaved NV12/NV21 UV pair or packed BGRA8888 pixel,
/// where the destination pixel stride must stay equal to the source's).
///
/// When [sourcePixelStride] is wider than [sampleBytes] -- Android's
/// `ImageFormatGroup.yuv420` reports separate U and V planes on some devices
/// with `bytesPerPixel == 2` each, i.e. the same interleaved chroma buffer
/// NV12/NV21 uses, just exposed as two `Image.Plane`s with a 1-byte pixel
/// offset between them, not one -- this **de-interleaves**: every other
/// source byte, the one belonging to this plane's channel, is kept, and the
/// stride-1 byte in between (the other channel's sample) is dropped. A tight
/// output that merely repeated the source's pixel stride would still leave
/// alternating bytes belonging to the other channel in what should be a pure
/// U or V plane, and native code that assumes `pixelStride == sampleBytes`
/// for planar I420 chroma would then read the wrong bytes.
YuvPlane _packPlane({
  required Uint8List source,
  required int rows,
  required int columns,
  required int sourceRowStride,
  required int sourcePixelStride,
  required int sampleBytes,
}) {
  final tightRowStride = columns * sampleBytes;
  final packed = Uint8List(rows * tightRowStride);
  for (var row = 0; row < rows; row++) {
    final sourceRowStart = row * sourceRowStride;
    final destRowStart = row * tightRowStride;
    if (sourcePixelStride == sampleBytes) {
      packed.setRange(destRowStart, destRowStart + tightRowStride, source, sourceRowStart);
      continue;
    }
    for (var col = 0; col < columns; col++) {
      final sourceSampleStart = sourceRowStart + col * sourcePixelStride;
      final destSampleStart = destRowStart + col * sampleBytes;
      for (var b = 0; b < sampleBytes; b++) {
        packed[destSampleStart + b] = source[sourceSampleStart + b];
      }
    }
  }
  return YuvPlane(rows, tightRowStride, sampleBytes, packed);
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
