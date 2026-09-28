import 'dart:typed_data';

/// One plane's geometry and bytes for an ABI v1 operation.
///
/// Carries the byte buffer and strides needed to build an ABI plane
/// descriptor. The backend stages [bytes], [rowStride], and [pixelStride] in
/// its memory and derives the sample width from the frame format.
///
/// It is not the public `YuvPlane` model; it contains only ABI input data.
class YuvAbiV1PlaneInput {
  /// Creates a plane input. The backend reads [bytes] for the operation and
  /// stages it in its memory before invocation.
  const YuvAbiV1PlaneInput({required this.bytes, required this.rowStride, required this.pixelStride});

  /// Row-major plane bytes, exactly `rowStride * height` long for the plane's
  /// logical height (full frame height for plane 0, chroma height for a
  /// 4:2:0 chroma plane).
  final Uint8List bytes;

  /// Bytes per row, including any trailing row padding.
  final int rowStride;

  /// Bytes between the start of consecutive samples in a row.
  final int pixelStride;
}

/// A source frame for an ABI v1 operation, containing format,
/// dimensions, and one plane for BGRA/RGBA, two for NV12, or three for I420.
///
/// The ABI derives color matrix and range from [format]: BT.601/limited for
/// I420 and NV12, none/none for BGRA and RGBA. Callers cannot supply values
/// that conflict with the format.
class YuvAbiV1FrameInput {
  /// Creates a frame input. [planes] must have exactly as many entries as
  /// [format] requires; the runner validates this before invoking the backend.
  const YuvAbiV1FrameInput({required this.format, required this.width, required this.height, required this.planes});

  /// One of the ABI v1 numeric format ids (`yuv_abi_v1_constants.dart`).
  final int format;

  /// Frame width in visible pixels.
  final int width;

  /// Frame height in visible pixels.
  final int height;

  /// One entry per plane the format requires, in ABI plane order (Y, then
  /// U/V or interleaved UV).
  final List<YuvAbiV1PlaneInput> planes;
}

/// Requested geometry and per-plane layout for the destination of an ABI v1
/// operation.
///
/// Unlike [YuvAbiV1FrameInput], this carries no plane bytes. The runner
/// allocates destination buffers using this layout and returns the resulting
/// bytes. Geometry-changing operations can provide dimensions different from
/// the source, as with a quarter-turn rotation.
class YuvAbiV1DestinationLayout {
  /// Creates a destination layout. [planeRowStrides]/[planePixelStrides] must
  /// have exactly as many entries as [format] requires, in ABI plane order.
  const YuvAbiV1DestinationLayout({
    required this.format,
    required this.width,
    required this.height,
    required this.planeRowStrides,
    required this.planePixelStrides,
  });

  /// One of the ABI v1 numeric format ids (`yuv_abi_v1_constants.dart`).
  final int format;

  /// Destination width in visible pixels.
  final int width;

  /// Destination height in visible pixels.
  final int height;

  /// Row stride to allocate for each destination plane, in ABI plane order.
  final List<int> planeRowStrides;

  /// Pixel stride to allocate for each destination plane, in ABI plane order.
  final List<int> planePixelStrides;
}

/// The bytes of a successfully completed ABI v1 operation, one entry per
/// destination plane in ABI plane order.
///
/// The runner returns this only after `YUV_STATUS_OK`; on failure it throws
/// without exposing destination bytes.
class YuvAbiV1FrameResult {
  /// Creates a result. Callers do not normally construct this directly; the
  /// runner does.
  const YuvAbiV1FrameResult(this.planes);

  /// One entry per destination plane, in ABI plane order.
  final List<Uint8List> planes;
}

/// A right/bottom-exclusive region of interest in source visible-pixel
/// coordinates. Passing `null` where a runner method accepts this selects the
/// whole frame.
class YuvAbiV1Region {
  /// Creates a region. The runner does not validate whether it lies inside
  /// the frame or is non-empty; validation by the ABI implementation is
  /// authoritative.
  const YuvAbiV1Region({required this.left, required this.top, required this.right, required this.bottom});

  /// Left edge, inclusive.
  final int left;

  /// Top edge, inclusive.
  final int top;

  /// Right edge, exclusive.
  final int right;

  /// Bottom edge, exclusive.
  final int bottom;
}
