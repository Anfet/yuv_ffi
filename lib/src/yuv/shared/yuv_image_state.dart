import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yuv_ffi/src/yuv/shared/yuv_codec.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane_bytes.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane_layout.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane_packing.dart';

/// The format, geometry, plane and revision state every `YuvImageImpl` backend
/// owns, with the accessor, allocation, copy and serialization logic that state
/// implies.
///
/// Each backend composes this state object and keeps its platform-specific
/// dispatch in its own implementation. This class has no backend imports.
///
/// It is internal: the public mutation model, and which operations a backend
/// supports at all, remain each backend's own contract. In particular sharing
/// state does not imply Web/native feature parity -- Web remains a partial WASM
/// backend.
class YuvImageState {
  /// Creates state for [format] at [width] x [height].
  ///
  /// When [planes] is given, it is validated against the format geometry
  /// first -- reading only, never copying or mutating the caller's planes --
  /// then adopted according to [layout]: [YuvPlaneLayout.preserve]
  /// deep-copies the caller's layout, including row and pixel padding, exactly
  /// as given. [YuvPlaneLayout.packed] (the default) copies only the visible
  /// samples straight out of the caller's own planes into a tightly packed
  /// layout instead, as `YuvImagePack.pack()` would -- there is no
  /// intermediate padded deep copy: a plane that is already tight is deep-
  /// copied once (the cheap [YuvPlanePacking.packPlane] fast path), and one
  /// that is not is packed directly from the validated caller plane, so at
  /// most one copy of each plane's bytes is ever made. When [planes] is
  /// `null`, one tightly packed plane per format plane is allocated and
  /// zero-filled -- [layout] is not consulted in that case, since there is no
  /// caller layout to preserve.
  ///
  /// For NV12, [allowLargerNvChromaStride] permits a gap between interleaved
  /// chroma pairs when a supplied plane has extra per-pair spacing. It defaults
  /// to `false`, which requires tightly spaced pairs.
  ///
  /// Throws [ArgumentError] for a non-positive dimension, a plane count that
  /// does not match [format], a plane that cannot hold its declared geometry,
  /// or (when [allowLargerNvChromaStride] is `false`) an interleaved chroma
  /// [uvPixelStride] other than exactly [YuvGeometry.nvChromaPixelStride] --
  /// always before any backend allocation.
  YuvImageState(
    this._format,
    this._width,
    this._height, {
    int yPixelStride = 1,
    int uvPixelStride = 1,
    Iterable<YuvPlane>? planes,
    bool allowLargerNvChromaStride = false,
    YuvPlaneLayout layout = YuvPlaneLayout.packed,
  }) : _allowLargerNvChromaStride = allowLargerNvChromaStride {
    YuvGeometry.validateDimensions(_width, _height);

    if (planes != null) {
      final given = planes is List<YuvPlane> ? planes : List<YuvPlane>.of(planes);
      YuvGeometry.validateImage(format: _format, width: _width, height: _height, planes: given, allowLargerNvChromaStride: allowLargerNvChromaStride);
      _planes = layout == YuvPlaneLayout.packed
          ? YuvPlanePacking.packAll(_format, _width, _height, given)
          : List<YuvPlane>.of(given.map((plane) => plane.copy()));
      return;
    }

    if (allowLargerNvChromaStride && _format == YuvPixelFormat.nv12 && uvPixelStride < YuvGeometry.nvChromaPixelStride) {
      // The relaxed nv12 path never silently clamps a too-small stride the way
      // the default allocation does (allocatePlanes below): an explicit
      // value below the packed-pair minimum is a caller mistake and must throw,
      // not be corrected into a different geometry than what was asked for.
      throw ArgumentError.value(
        uvPixelStride,
        'uvPixelStride',
        'Interleaved NV12 chroma requires a pixel stride of at least ${YuvGeometry.nvChromaPixelStride}',
      );
    }

    _planes = allocatePlanes(format: _format, width: _width, height: _height, yPixelStride: yPixelStride, uvPixelStride: uvPixelStride);

    // Validate the geometry just allocated as well: a caller-supplied zero or
    // negative stride would otherwise produce a degenerate plane and still
    // reach a backend call.
    YuvGeometry.validateImage(format: _format, width: _width, height: _height, planes: _planes, allowLargerNvChromaStride: allowLargerNvChromaStride);
  }

  /// Tightly packed, zero-filled planes for [format] at [width] x [height].
  ///
  /// Exposed separately from the constructor because a backend sometimes needs
  /// the planes without an owning state object -- notably the stub's format
  /// conversions, which replace planes in place.
  static List<YuvPlane> allocatePlanes({
    required YuvPixelFormat format,
    required int width,
    required int height,
    int yPixelStride = 1,
    int uvPixelStride = 1,
  }) {
    // BGRA stores four bytes per pixel, so its packed plane never uses the
    // generic single-byte luma default.
    final lumaPixelStride = format == YuvPixelFormat.bgra8888 ? 4 : yPixelStride;
    final yPlane = YuvPlane(height, width * lumaPixelStride, lumaPixelStride);
    final uvWidth = YuvGeometry.chromaWidth(width);
    final uvHeight = YuvGeometry.chromaHeight(height);

    switch (format) {
      case YuvPixelFormat.nv12:
        // Interleaved chroma always stores a (U, V) pair per sample, so a
        // pixelStride below 2 cannot hold what native code writes.
        final nvPixelStride = uvPixelStride < YuvGeometry.nvChromaPixelStride ? YuvGeometry.nvChromaPixelStride : uvPixelStride;
        return [yPlane, YuvPlane(uvHeight, uvWidth * nvPixelStride, nvPixelStride)];
      case YuvPixelFormat.i420:
        return [yPlane, YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride), YuvPlane(uvHeight, uvWidth * uvPixelStride, uvPixelStride)];
      case YuvPixelFormat.bgra8888:
        return [yPlane];
    }
  }

  YuvPixelFormat _format;
  int _width;
  int _height;
  bool _allowLargerNvChromaStride;
  List<YuvPlane> _planes = const [];
  int _revision = 0;

  /// Current pixel format.
  YuvPixelFormat get format => _format;

  /// Visible width in pixels.
  int get width => _width;

  /// Visible height in pixels.
  int get height => _height;

  /// Monotonic revision counter, advanced by [bumpRevision].
  int get revision => _revision;

  /// Unmodifiable view of the planes, in format order.
  List<YuvPlane> get planes => List<YuvPlane>.unmodifiable(_planes);

  /// The luma or packed plane.
  ///
  /// Every format has one, and every constructor either allocates the full
  /// format plane set or validates a caller-supplied one against it, so this
  /// always returns a real plane. There is deliberately no empty/unavailable
  /// fallback: the state can never hold fewer planes than its format requires
  /// (see the class doc of [YuvImageState] and the accessor contract tests in
  /// `test/yuv_image_state_contract_test.dart`). A backend that broke that
  /// invariant would get a loud [RangeError] here rather than a silent
  /// zero-length sentinel plane whose bytes no caller can use.
  YuvPlane get yPlane => _planes[0];

  /// The U plane (I420) or the interleaved UV plane (NV).
  ///
  /// Only valid for a format that has chroma; see [yPlane] on why this does not
  /// fall back to a sentinel. Use [u] to ask whether it exists.
  YuvPlane get uPlane => _planes[1];

  /// The V plane. Only valid for I420; see [yPlane] and [v].
  YuvPlane get vPlane => _planes[2];

  /// The U/UV plane, or `null` for a format without chroma.
  YuvPlane? get u => _planes.length > 1 ? _planes[1] : null;

  /// The V plane, or `null` for a format that does not keep one.
  YuvPlane? get v => _planes.length > 2 ? _planes[2] : null;

  /// Visible geometry as a [ui.Size].
  ui.Size get size => ui.Size(_width.toDouble(), _height.toDouble());

  /// Pixel stride of the luma/packed plane, for rebuilding a matching image.
  int get yPixelStride => yPlane.pixelStride;

  /// Pixel stride of the chroma plane, or `1` when the format has none.
  int get uvPixelStride => u?.pixelStride ?? 1;

  /// Whether replacements and derived images may retain gapped NV12 chroma.
  bool get allowsLargerNvChromaStride => _allowLargerNvChromaStride;

  /// Advances [revision] by one.
  void bumpRevision() => _revision++;

  /// Replaces format, geometry and planes in one step and advances [revision].
  ///
  /// Every mutating backend operation that changes what the image holds ends
  /// here, so a partially updated state is not representable: the fields move
  /// together or not at all. [planes] is adopted as given -- callers that must
  /// not share buffers with the source pass copies.
  void replace({
    required YuvPixelFormat format,
    required int width,
    required int height,
    required List<YuvPlane> planes,
    bool? allowLargerNvChromaStride,
  }) {
    _format = format;
    _width = width;
    _height = height;
    _planes = planes;
    if (allowLargerNvChromaStride != null) {
      _allowLargerNvChromaStride = allowLargerNvChromaStride;
    }
    _revision++;
  }

  /// Validates [planes] against this state's current format and geometry,
  /// copies them in, and atomically replaces the plane set, advancing
  /// [revision] exactly once.
  ///
  /// [planes] is copied and validated on that copy before [_planes] is
  /// touched, so a rejected call leaves format, geometry, the existing plane
  /// objects and [revision] exactly as they were -- a caller cannot observe a
  /// half-applied replacement. Format and geometry are unchanged by this
  /// call; only the plane content moves.
  ///
  /// Throws [ArgumentError] when [planes] does not match [format] at
  /// [width] x [height].
  void applyPlanes(Iterable<YuvPlane> planes) {
    final copied = List<YuvPlane>.of(planes.map((plane) => plane.copy()));
    YuvGeometry.validateImage(format: _format, width: _width, height: _height, planes: copied, allowLargerNvChromaStride: _allowLargerNvChromaStride);
    _planes = copied;
    _revision++;
  }

  // Multi-step operations stage all results before calling [replace] once, so
  // a failure cannot publish an intermediate image state.

  /// Every plane's bytes concatenated in format order, as a fresh buffer.
  Uint8List getBytes() => YuvPlaneBytes.concat(_planes);

  /// Planes for a deep copy of this state.
  ///
  /// A blank copy keeps every plane's declared geometry and zeroes the whole
  /// allocation, so padded metadata survives. Rebuilding through
  /// [allocatePlanes] instead would produce tight planes and silently drop the
  /// padding.
  List<YuvPlane> copiedPlanes({bool blank = false}) => [
    for (final plane in _planes) blank ? YuvPlane(plane.height, plane.rowStride, plane.pixelStride) : plane.copy(),
  ];

  /// Encodes this state into the `yuv_ffi` container format.
  Uint8List encode() => YuvCodec.encode(format: _format, width: _width, height: _height, planes: _planes);

  /// Decodes [stream] and replaces this state with what it held.
  ///
  /// Decoding completes into a validated draft before anything is replaced, so
  /// a malformed payload cannot leave the image half-updated and leaves
  /// [revision] alone as well.
  Future<void> decodeAndReplace(Stream<List<int>> stream) async {
    final draft = await YuvCodec.decodeStream(stream);
    replace(
      format: draft.format,
      width: draft.width,
      height: draft.height,
      planes: draft.planes,
      allowLargerNvChromaStride: draft.format == YuvPixelFormat.nv12 && draft.planes[1].pixelStride > YuvGeometry.nvChromaPixelStride,
    );
  }

  /// Whether the BGRA luma plane is tightly packed, so an operation that
  /// addresses a tight scratch buffer through the source stride is safe.
  bool get isTightBgra => YuvGeometry.isTightBgra(yPlane, _width);

  /// Rejects a padded BGRA plane before an operation that cannot handle it.
  ///
  /// Several native BGRA effects allocate a tight `width * height * 4` scratch
  /// buffer but address it through the source row stride, so a padded plane
  /// makes them write past the allocation. The WASM build shares those sources,
  /// so both backends reject this input before dispatch.
  void requireTightBgraFor(String operation) {
    if (_format != YuvPixelFormat.bgra8888 || isTightBgra) {
      return;
    }
    throw ArgumentError.value(
      yPlane.rowStride,
      'yPlane.rowStride',
      '$operation does not support a padded BGRA plane yet; expected a tight '
          'row stride of ${_width * 4}. Repack the plane before calling it.',
    );
  }

  /// The destination rectangle [rect] clamps to, in whole pixels, or `null`
  /// when it selects nothing and the crop is therefore a no-op.
  ///
  /// Shared so every backend clamps a crop identically: `floor` the near edges,
  /// `ceil` the far ones, and clamp both into the current geometry.
  ({int left, int top, int width, int height})? clampCrop(ui.Rect rect) {
    final left = rect.left.floor().clamp(0, _width).toInt();
    final top = rect.top.floor().clamp(0, _height).toInt();
    final right = rect.right.ceil().clamp(left, _width).toInt();
    final bottom = rect.bottom.ceil().clamp(top, _height).toInt();
    final cropWidth = right - left;
    final cropHeight = bottom - top;
    if (cropWidth <= 0 || cropHeight <= 0) {
      return null;
    }
    return (left: left, top: top, width: cropWidth, height: cropHeight);
  }

  /// [rotation] normalized to `0`, `90`, `180` or `270`.
  ///
  /// Takes the degrees rather than the enum so `shared/` does not need to know
  /// about the public rotation type from the backend's own import graph.
  static int normalizeRotationDegrees(int degrees) => (degrees < 0 ? 360 - degrees.abs() : degrees) % 360;

  /// Copies the logical four-byte samples of [tight] into this state's own
  /// BGRA layout, leaving row and pixel padding untouched.
  ///
  /// The shared BGRA C converter addresses its destination as a tight buffer,
  /// so a padded destination is filled by staging into a tight image and then
  /// copying samples back through both layouts' strides. Both backends do this
  /// the same way, so both preserve identical padding.
  void copyTightBgraSamplesFrom(YuvPlane tight) {
    const int bytesPerPixel = 4;
    final destination = yPlane;
    for (int row = 0; row < _height; row++) {
      final sourceRowStart = row * tight.rowStride;
      final destinationRowStart = row * destination.rowStride;
      for (int column = 0; column < _width; column++) {
        final source = sourceRowStart + column * bytesPerPixel;
        final target = destinationRowStart + column * destination.pixelStride;
        destination.bytes.setRange(target, target + bytesPerPixel, tight.bytes, source);
      }
    }
  }

  /// The BGRA plane's bytes as a fresh, tightly packed `width * height * 4`
  /// buffer, repacking rows only when the plane declares row or pixel padding.
  ///
  /// Per-pixel gaps and row padding are skipped. Only the four logical bytes
  /// of each pixel are copied using the plane's `rowStride` and `pixelStride`, so
  /// neither kind of padding leaks into the tightly packed result. The result
  /// is always a fresh copy, never a view onto the mutable plane buffer, and
  /// the source plane is never modified.
  Uint8List packedBgraBytes() {
    final expectedRowStride = _width * 4;
    if (yPlane.rowStride == expectedRowStride && yPlane.pixelStride == 4) {
      return Uint8List.fromList(yPlane.bytes);
    }
    final packed = Uint8List(_width * _height * 4);
    final source = yPlane.bytes;
    for (int row = 0; row < _height; row++) {
      final sourceRowStart = row * yPlane.rowStride;
      final destinationRowStart = row * expectedRowStride;
      for (int column = 0; column < _width; column++) {
        final sourceOffset = sourceRowStart + column * yPlane.pixelStride;
        final destinationOffset = destinationRowStart + column * 4;
        packed.setRange(destinationOffset, destinationOffset + 4, source, sourceOffset);
      }
    }
    return packed;
  }

  /// Rejects an RGBA8888 buffer that does not hold exactly one frame of this
  /// geometry.
  void validateRgba8888Length(int length) {
    final expectedLength = _width * _height * 4;
    if (length != expectedLength) {
      throw ArgumentError.value(length, 'bytes.length', 'Expected $expectedLength bytes for RGBA8888 frame ${_width}x$_height');
    }
  }

  @override
  String toString() => '${_format.name}, $_width:$_height / ${_planes.length}';
}
