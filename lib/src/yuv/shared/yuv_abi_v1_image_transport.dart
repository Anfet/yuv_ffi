import 'dart:typed_data';

import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_frame.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_constants.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';

/// Translates between the public Dart image shape (the legacy format enum plus
/// [YuvPlane] list) and the ABI v1 descriptors the runners consume (YUV-50,
/// YUV-51).
///
/// A runner deliberately speaks only in numeric ABI format ids, byte buffers
/// and strides: it is the transport for `yuv_*_v1` and knows nothing about the
/// public API. This is the one place that maps the two together, so no public
/// backend builds a descriptor by hand and the sides cannot drift into
/// disagreeing about plane order or chroma extents.
///
/// It lives in `shared/` rather than beside either backend because both use it
/// unchanged: the IO runner stages these descriptors into native memory through
/// `dart:ffi`, the Web runner stages the identical descriptors into WASM linear
/// memory. Format mapping, chroma extents and padding preservation are decided
/// here once, so IO and Web cannot disagree about them.
///
/// A runner always allocates a *tight* destination, while a public image may
/// legitimately carry row and pixel padding the contract requires to survive an
/// operation. [applyTo] is therefore not a byte copy: it walks the logical
/// samples through both layouts' strides and leaves every padding byte of the
/// receiving plane exactly as it was.
abstract final class YuvAbiV1ImageTransport {
  /// The ABI v1 numeric format id for [format].
  ///
  /// The public `nv21` label maps onto canonical NV12 storage: ABI v1 defines
  /// no separate NV21 format value, and the project's `nv21` keeps its
  /// historical `(U, V)` byte order under that same id (section 14, Q1).
  // ignore: deprecated_member_use_from_same_package
  static int abiFormat(YuvFileFormat format) => switch (format) {
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.i420 => yuvFormatI420,
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.nv21 => yuvFormatNv12,
    // ignore: deprecated_member_use_from_same_package
    YuvFileFormat.bgra8888 => yuvFormatBgra8888,
  };

  /// A source descriptor over [planes], read as they are.
  ///
  /// The planes' own row and pixel strides are passed through verbatim: native
  /// validation walks active samples through both strides, so a padded source
  /// needs no repacking here.
  // ignore: deprecated_member_use_from_same_package
  static YuvAbiV1FrameInput source({required YuvFileFormat format, required int width, required int height, required List<YuvPlane> planes}) {
    return YuvAbiV1FrameInput(
      format: abiFormat(format),
      width: width,
      height: height,
      planes: [for (final plane in planes) YuvAbiV1PlaneInput(bytes: plane.bytes, rowStride: plane.rowStride, pixelStride: plane.pixelStride)],
    );
  }

  /// A source descriptor over a single RGBA8888 buffer.
  ///
  /// RGBA is valid only as a `yuv_convert_v1` source (section 11), so it has no
  /// legacy format enum of its own and is built directly from the caller's tight
  /// `width * height * 4` buffer.
  static YuvAbiV1FrameInput rgbaSource({required Uint8List bytes, required int width, required int height}) {
    return YuvAbiV1FrameInput(
      format: yuvFormatRgba8888,
      width: width,
      height: height,
      planes: [YuvAbiV1PlaneInput(bytes: bytes, rowStride: width * 4, pixelStride: 4)],
    );
  }

  /// A tight destination layout for [format] at [width] x [height].
  ///
  /// Used where the caller needs to name a destination format the runner would
  /// not otherwise derive from the source -- that is, conversions. Every other
  /// operation keeps the source format and lets the runner build this itself.
  // ignore: deprecated_member_use_from_same_package
  static YuvAbiV1DestinationLayout destination({required YuvFileFormat format, required int width, required int height}) {
    final int abi = abiFormat(format);
    final int planeCount = yuvAbiV1PlaneCount(abi);
    final rowStrides = <int>[];
    final pixelStrides = <int>[];
    for (int planeIndex = 0; planeIndex < planeCount; planeIndex++) {
      final int sampleBytes = yuvAbiV1SampleBytes(abi, planeIndex);
      final int planeWidth = planeIndex == 0 ? width : yuvAbiV1ChromaExtent(width);
      pixelStrides.add(sampleBytes);
      rowStrides.add(planeWidth * sampleBytes);
    }
    return YuvAbiV1DestinationLayout(format: abi, width: width, height: height, planeRowStrides: rowStrides, planePixelStrides: pixelStrides);
  }

  /// Tightly packed planes holding [result], for an image of [format] at
  /// [width] x [height].
  ///
  /// This is the shape a `to*` conversion and a geometry-changing operation
  /// need: the receiver adopts a whole new plane set, so there is no prior
  /// padding to preserve and the runner's tight buffers can be adopted
  /// directly.
  // ignore: deprecated_member_use_from_same_package
  static List<YuvPlane> planesOf({required YuvAbiV1FrameResult result, required YuvFileFormat format, required int width, required int height}) {
    final int abi = abiFormat(format);
    final planes = <YuvPlane>[];
    for (int planeIndex = 0; planeIndex < result.planes.length; planeIndex++) {
      final int sampleBytes = yuvAbiV1SampleBytes(abi, planeIndex);
      final int planeWidth = planeIndex == 0 ? width : yuvAbiV1ChromaExtent(width);
      final int planeHeight = planeIndex == 0 ? height : yuvAbiV1ChromaExtent(height);
      planes.add(YuvPlane(planeHeight, planeWidth * sampleBytes, sampleBytes, result.planes[planeIndex]));
    }
    return planes;
  }

  /// Writes [result]'s logical samples into [planes], keeping their padding.
  ///
  /// [planes] must already have the geometry [result] was produced for; this is
  /// the in-place case, where the receiver keeps the layout it was constructed
  /// with. Only the active `planeWidth x planeHeight` samples are written, so
  /// row gaps, pixel gaps and any bytes past the last sample keep the values
  /// they had before the operation -- the padding-preservation half of the
  /// section 11 stride contract, which the runner's tight destination cannot
  /// express on its own.
  static void applyTo({
    required YuvAbiV1FrameResult result,
    required List<YuvPlane> planes,
    // ignore: deprecated_member_use_from_same_package
    required YuvFileFormat format,
    required int width,
    required int height,
  }) {
    final int abi = abiFormat(format);
    for (int planeIndex = 0; planeIndex < result.planes.length; planeIndex++) {
      final int sampleBytes = yuvAbiV1SampleBytes(abi, planeIndex);
      final int planeWidth = planeIndex == 0 ? width : yuvAbiV1ChromaExtent(width);
      final int planeHeight = planeIndex == 0 ? height : yuvAbiV1ChromaExtent(height);
      final int sourceRowStride = planeWidth * sampleBytes;
      final Uint8List source = result.planes[planeIndex];
      final YuvPlane target = planes[planeIndex];
      final Uint8List destination = target.bytes;

      if (target.rowStride == sourceRowStride && target.pixelStride == sampleBytes) {
        // A tight receiver has no padding to step around, so the whole plane
        // moves in one copy.
        destination.setRange(0, source.length, source);
        continue;
      }

      if (target.pixelStride == sampleBytes) {
        for (int row = 0; row < planeHeight; row++) {
          final int sourceRowStart = row * sourceRowStride;
          final int destinationRowStart = row * target.rowStride;
          destination.setRange(destinationRowStart, destinationRowStart + sourceRowStride, source, sourceRowStart);
        }
        continue;
      }

      for (int row = 0; row < planeHeight; row++) {
        final int sourceRowStart = row * sourceRowStride;
        final int destinationRowStart = row * target.rowStride;
        for (int column = 0; column < planeWidth; column++) {
          final int sourceOffset = sourceRowStart + column * sampleBytes;
          final int destinationOffset = destinationRowStart + column * target.pixelStride;
          destination.setRange(destinationOffset, destinationOffset + sampleBytes, source, sourceOffset);
        }
      }
    }
  }
}
