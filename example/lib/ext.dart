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
        return YuvImage.nv12(width, height, planes: planes, layout: YuvPlaneLayout.preserve);
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
  /// Builds an [InputImage] whose bytes match what its declared
  /// [InputImageMetadata.format] actually promises.
  ///
  /// PACK-01D: `google_mlkit_commons` 0.11.0's Android byte-array path only
  /// recognizes NV21, YV12 and YUV_420_888 (`InputImageFormat.yuv420`, despite
  /// the name, is iOS-only -- see that enum's own doc comments) -- not
  /// arbitrary separate I420 planes and not this package's UV-ordered `nv12`.
  /// Labelling either of those `yuv420`/`nv21` without also rearranging the
  /// bytes fed a decoder metadata that lied about the layout it was reading,
  /// silently corrupting every chroma sample. This builds one tight `Y` plane
  /// followed by one tight interleaved chroma plane in **V, U** order (true
  /// NV21) from either source format, de-interleaving/repacking around
  /// whatever row padding or pixel gap the source planes declare, and labels
  /// the result [InputImageFormat.nv21]. iOS gets a tight packed BGRA buffer
  /// (`bytesPerRow == width * 4`), the only geometry `bgra8888` promises.
  InputImage toInputImage() {
    switch (format) {
      case YuvPixelFormat.i420:
      case YuvPixelFormat.nv12:
        final bytes = _toNv21Bytes();
        final meta = InputImageMetadata(size: size, rotation: InputImageRotation.rotation0deg, format: InputImageFormat.nv21, bytesPerRow: width);
        return InputImage.fromBytes(bytes: bytes, metadata: meta);

      case YuvPixelFormat.bgra8888:
        // pack() is a no-op copy when already tight, so this only allocates
        // a second time for a genuinely padded source.
        final tight = copy().pack();
        final meta = InputImageMetadata(
          size: size,
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: width * 4,
        );
        return InputImage.fromBytes(bytes: tight.yPlane.bytes, metadata: meta);
    }
  }

  /// Builds `Y + VU` bytes (true NV21 order) from this image's planes,
  /// regardless of whether it is I420 (separate `U`/`V` planes) or this
  /// package's `nv12` (one `U`-before-`V` interleaved chroma plane), and
  /// regardless of any row padding or pixel gap those planes declare.
  ///
  /// Packs a copy first so every plane below is tight (I420 chroma at
  /// `pixelStride == 1`, `nv12`'s interleaved chroma at `pixelStride == 2`),
  /// leaving only the U/V byte order left to fix up here.
  Uint8List _toNv21Bytes() {
    final tight = copy().pack();
    final chromaWidth = (width + 1) ~/ 2;
    final chromaHeight = (height + 1) ~/ 2;
    final tightY = tight.yPlane.bytes;

    final vu = Uint8List(chromaHeight * chromaWidth * 2);
    if (tight.format == YuvPixelFormat.nv12) {
      final uv = tight.uPlane.bytes;
      for (var i = 0; i < chromaWidth * chromaHeight; i++) {
        vu[i * 2] = uv[i * 2 + 1]; // V
        vu[i * 2 + 1] = uv[i * 2]; // U
      }
    } else {
      final u = tight.uPlane.bytes;
      final v = tight.vPlane.bytes;
      for (var i = 0; i < chromaWidth * chromaHeight; i++) {
        vu[i * 2] = v[i];
        vu[i * 2 + 1] = u[i];
      }
    }

    final result = Uint8List(tightY.length + vu.length);
    result.setRange(0, tightY.length, tightY);
    result.setRange(tightY.length, result.length, vu);
    return result;
  }
}
