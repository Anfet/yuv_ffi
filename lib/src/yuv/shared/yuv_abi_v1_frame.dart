import 'dart:typed_data';

/// One plane's geometry and bytes, as the ABI v1 typed IO runner needs them.
///
/// This is deliberately a plain value carrying only what
/// `YuvConstPlaneV1`/`YuvMutablePlaneV1` (`src/yuv/abi/h/yuv_abi_v1.h`)
/// require: `bytes.length` is the descriptor's `length`, [rowStride] and
/// [pixelStride] are copied verbatim, and `sampleBytes` is derived from the
/// frame's format rather than carried here (every plane's `sampleBytes` is
/// fixed by format + plane index in ABI v1, see section 11's format matrix).
///
/// It is not [YuvPlane]: that type is the public Dart-facing plane shape and
/// belongs to YUV-28's public API redesign, which this task does not touch.
class YuvAbiV1PlaneInput {
  /// Creates a plane input. [bytes] is read but never retained past the
  /// runner call that consumes it -- the runner copies into native memory
  /// immediately.
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

/// A source frame for the ABI v1 typed IO runner: format, geometry, and one
/// plane per the format's plane count (1 for BGRA/RGBA, 2 for NV12, 3 for
/// I420 -- see `yuv_validated_view_plane_count` in
/// `src/yuv/utils/h/validated_view.h`, mirrored by the format matrix in
/// `docs/api-abi-0.3-design.md` section 11).
///
/// `colorMatrix`/`colorRange` are not fields here: they are fixed by
/// [format] under ABI v1 (BT.601/limited for I420/NV12, none/none for
/// BGRA/RGBA -- section 9), so the runner derives them rather than accepting
/// a value that could disagree with the format and be rejected as
/// `UNSUPPORTED_COLOR` before the caller even gets to see why.
class YuvAbiV1FrameInput {
  /// Creates a frame input. [planes] must have exactly as many entries as
  /// [format] requires; the runner validates this before any native call.
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

/// Requested geometry and per-plane layout for the destination the ABI v1
/// typed IO runner allocates and, on success, copies back into.
///
/// Unlike [YuvAbiV1FrameInput], this does not carry bytes: the runner
/// allocates and zero-seeds the destination itself (section 13, step 3 --
/// "allocate and seed destination staging where preservation is required"),
/// then returns the result bytes rather than requiring the caller to
/// pre-allocate a buffer whose size it may not know until validation exposes
/// it (for example, rotate 90/270 transposes width and height).
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
/// Only constructed after a `YUV_STATUS_OK` result: the runner never returns
/// this for a non-zero status (section 13, step 6 -- "map non-zero status to
/// Dart exception without publishing destination").
class YuvAbiV1FrameResult {
  /// Creates a result. Callers do not normally construct this directly; the
  /// runner does.
  const YuvAbiV1FrameResult(this.planes);

  /// One entry per destination plane, in ABI plane order.
  final List<Uint8List> planes;
}

/// A right/bottom-exclusive region of interest in source visible-pixel
/// coordinates, mirroring `YuvRegionOptionsV1` (section 10) in its enabled
/// form. Passing `null` where a runner method accepts this means "whole
/// frame" (a disabled region).
class YuvAbiV1Region {
  /// Creates a region. A runner does not itself validate that it lies
  /// inside the frame or is non-empty -- native validation is authoritative
  /// (section 11) and reports `INVALID_ARGUMENT` for a malformed rectangle.
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
