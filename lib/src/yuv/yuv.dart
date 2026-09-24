import 'dart:ui' as ui;
import 'package:yuv_ffi/src/yuv/shared/yuv_codec.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_geometry.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_native_status.dart' show YuvNativeException;
import 'package:yuv_ffi/src/yuv/shared/yuv_operation.dart' show YuvOperation;

import 'impl/yuv_stub.dart' if (dart.library.ffi) 'impl/io/yuv_image.dart' if (dart.library.js_interop) 'impl/web/yuv_web.dart';

export 'shared/yuv_deprecated_api.dart';

// `YuvImageImpl` (whichever backend this conditional import resolves to) is
// deliberately not exported: it is an internal implementation detail behind
// the `YuvImage` interface, reachable by callers only through the factory
// constructors below. REL-06 hides it; earlier revisions exported the impl
// library wholesale.

/// Represents an in-memory image in one of supported YUV/BGRA formats.
///
/// Use factory constructors to create an instance for a specific format:
/// [YuvImage.i420], [YuvImage.nv12], or [YuvImage.bgra].
///
/// Mutation model (`io` and `web` backends):
/// - In-place (returns `this`): [applyGrayscale], [applyBlackWhite],
///   [applyNegate], [applyGaussianBlur], [applyMeanBlur], [applyBoxBlur],
///   [applyCrop], [applyFlipHorizontal], [applyFlipVertical],
///   [applyRotation], [applyFormat], [applyChromaSwap], [applyRgbaBytes],
///   [applyPlanes].
/// - Returns a new, independent image: [copy], [cropped], [rotated],
///   [toI420], [toNv12], [toBgra], and the static [YuvImage.decode].
///
/// The published `0.2.4` instance-method surface (`blackwhite()`, `gaussianBlur()`,
/// `crop()`, `swapNv()`, `toYuvNv21()`, `save()`, `load()`, and the rest)
/// still compiles: it lives in the deprecated `DeprecatedYuvImageApi`
/// extension, forwarding to the members above (`doc/api-abi-0.4-design.md`
/// sections 4 and 8). `save()` forwards to [encodeTo] with identical bytes;
/// `load()` mutates in place through a package-private atomic
/// state-replacement adapter and throws [UnsupportedError] without mutating
/// on a foreign `implements YuvImage` -- new code uses the static
/// [YuvImage.decode], which returns a new image and never mutates a receiver.
///
/// Breaking change for a foreign `implements YuvImage`: every `apply*`/`to*`
/// member added for `0.4.0` is a required interface member, so an external
/// class that implements this interface directly (rather than extending a
/// backend this package provides) must implement them too. This is the same
/// breaking change already introduced when those members were added; nothing
/// here adds further required members beyond that set.
abstract interface class YuvImage {
  /// Pixel format of the current image.
  ///
  /// A legacy `nv21`-labeled image (created through the legacy `nv21`
  /// or unnamed factory) reports
  /// [YuvPixelFormat.nv12] here: the truthful name for the same canonical
  /// semi-planar storage (section 4, lines ~112/144 of
  /// `doc/api-abi-0.4-design.md`).
  YuvPixelFormat get format;

  /// Image width in pixels.
  int get width;

  /// Image height in pixels.
  int get height;

  /// Raw image planes in format-specific order.
  List<YuvPlane> get planes;

  /// Luma (Y) plane.
  YuvPlane get yPlane;

  /// U plane for planar formats, or interleaved UV/VU plane for semi-planar.
  YuvPlane get uPlane;

  /// V plane for planar formats.
  YuvPlane get vPlane;

  /// Convenience size object built from [width] and [height].
  ui.Size get size;

  /// Creates an I420 image.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// [yPixelStride] and [uvPixelStride] define byte step for allocated planes
  /// when [planes] is omitted.
  /// If [planes] is provided, plane data is copied from it.
  factory YuvImage.i420(int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl.i420;

  /// Creates an NV21-labeled image.
  ///
  /// Note: in this project the `nv21` label is intentionally mapped to UV order.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// [yPixelStride] and [uvPixelStride] define byte step for allocated planes
  /// when [planes] is omitted.
  /// If [planes] is provided, plane data is copied from it.
  @Deprecated('Legacy nv21 label contains UV bytes; use YuvImage.nv12().')
  factory YuvImage.nv21(int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl.nv21;

  /// Creates a BGRA8888 image.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// If [planes] is provided, plane data is copied from it.
  factory YuvImage.bgra(int width, int height, {Iterable<YuvPlane>? planes}) = YuvImageImpl.bgra;

  /// Creates an image by explicit legacy [format].
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// [yPixelStride] and [uvPixelStride] define byte step for allocated planes
  /// when [planes] is omitted.
  /// If [planes] is provided, plane data is copied from it.
  @Deprecated('Use a named factory (YuvImage.i420, YuvImage.nv12, YuvImage.bgra) or YuvImage.allocate().')
  factory YuvImage(YuvFileFormat format, int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl;

  /// Creates an NV12 image with the truthfully named semi-planar storage.
  ///
  /// Canonical replacement for the legacy `nv21` factory: same interleaved chroma
  /// storage, without claiming the legacy NV21 byte order.
  ///
  /// [width] and [height] are image dimensions in pixels.
  /// [yPixelStride] and [uvPixelStride] define byte step for allocated planes
  /// when [planes] is omitted; [uvPixelStride] defaults to `2`, matching the
  /// interleaved `(U, V)` pair every sample stores.
  /// If [planes] is provided, plane data is copied from it.
  factory YuvImage.nv12(int width, int height, {int yPixelStride, int uvPixelStride, Iterable<YuvPlane>? planes}) = YuvImageImpl.nv12;

  /// Allocates a new tightly packed, zero-filled image for [format] at
  /// [width] x [height].
  ///
  /// Unlike the named factories, this always produces tight planes with no
  /// row or pixel padding. It replaces `copy(blank: true)` only when the
  /// former image was tight. To preserve a padded or pixel-gapped layout,
  /// use the matching named factory with zeroed [YuvPlane] instances whose
  /// `height`, `rowStride`, and `pixelStride` match the source planes.
  ///
  /// Throws [ArgumentError] for a non-positive dimension.
  factory YuvImage.allocate(YuvPixelFormat format, int width, int height) = YuvImageImpl.allocate;

  /// Creates a new image of [format] at [width] x [height], filled by
  /// converting [bytes] from RGBA8888.
  ///
  /// [bytes] must hold exactly `width * height * 4` tightly packed RGBA
  /// bytes; RGBA8888 is an ABI input-only format and never a storable
  /// [YuvPixelFormat] of its own.
  ///
  /// Throws [ArgumentError] when [bytes] does not have the exact expected
  /// length, or for a non-positive dimension.
  factory YuvImage.fromRgbaBytes(Uint8List bytes, {required int width, required int height, required YuvPixelFormat format}) =
      YuvImageImpl.fromRgbaBytes;

  /// Creates a copy as a new image instance.
  ///
  /// If [blank] is `true`, returns an image with the same geometry, plane
  /// `rowStride`, and `pixelStride`, with zeroed bytes. Use
  /// [YuvImage.allocate] only when a tight replacement layout is intended.
  YuvImage copy({@Deprecated('Use YuvImage.allocate() for a tight blank image.') bool blank = false});

  /// Validates [planes] against this image's format and geometry, copies
  /// them in, and atomically replaces the current plane set.
  ///
  /// On success, every previously obtained [planes]/[yPlane]/[uPlane]/[vPlane]
  /// reference becomes stale: it still points at the storage this image held
  /// before the call, not the new one. Callers must re-fetch plane references
  /// afterward. The revision advances exactly once.
  ///
  /// Throws [ArgumentError] when [planes] does not match this image's format
  /// and geometry. [planes] is copied and validated on that copy before this
  /// image's own plane set is replaced, so a rejected call never touches it:
  /// this image's bytes, metadata and revision are left exactly as they were.
  ///
  /// Returns `this`.
  YuvImage applyPlanes(Iterable<YuvPlane> planes);

  /// Serializes this image into [sink].
  ///
  /// Does not mutate this image. Throws when [sink] rejects writes.
  Future<void> encodeTo(Sink<List<int>> sink) => throw UnimplementedError();

  /// Decodes [stream] into a new, independent image.
  ///
  /// Never mutates an existing instance -- there is no receiver, only a fresh
  /// image built from the decoded payload (`doc/api-abi-0.4-design.md`
  /// sections 4 and 8; the legacy mutating `load(stream)` moved to the
  /// deprecated `DeprecatedYuvImageApi.load` extension, which additionally
  /// requires a package-private atomic state-replacement adapter).
  ///
  /// Throws [FormatException] when [stream] holds a malformed or unsupported
  /// (for example a `0.2.4` version-1) payload.
  static Future<YuvImage> decode(Stream<List<int>> stream) async {
    final draft = await YuvCodec.decodeStream(stream);
    return YuvImageImpl(
      draft.format,
      draft.width,
      draft.height,
      planes: draft.planes,
      // ignore: deprecated_member_use_from_same_package
      allowLargerNvChromaStride: draft.format == YuvFileFormat.nv21 && draft.planes[1].pixelStride > YuvGeometry.nvChromaPixelStride,
    );
  }

  /// Converts to Flutter [ui.Image].
  ///
  /// Throws if pixel decode fails in the underlying engine.
  Future<ui.Image> toImage() => throw UnimplementedError();

  // -- 0.4.0 `apply*`/`to*` surface (doc/api-abi-0.4-design.md sections 2-4,
  // 13) --------------------------------------------------------------------
  //
  // Every `apply*` below calls `yuvRequireCapability` first, before any
  // allocation, native/WASM invocation, or state change (todo.md REL-04's
  // post-REL-09 addendum). On success it mutates in place, advances the
  // revision exactly once, and returns `identical(this)`. On failure --
  // capability, argument, or a non-zero native status -- bytes, format,
  // geometry and revision are left exactly as they were. A defined no-op
  // (radius 0, an empty normalized crop/ROI, rotation 0, same-format
  // `applyFormat`) short-circuits before dispatch and does not advance the
  // revision. The legacy instance methods that used to live directly above
  // this surface (`blackwhite()`, `crop()`, `swapNv()`, and the rest) were
  // retired into the deprecated `DeprecatedYuvImageApi` extension (REL-06),
  // which forwards every one of them to a member below.

  /// Replaces the current pixel content from tight RGBA8888 [bytes], in this
  /// image's own format and geometry, and returns `this`.
  ///
  /// [bytes] must hold exactly `width * height * 4` bytes.
  ///
  /// Throws [ArgumentError] for a wrong [bytes] length, [UnsupportedError]
  /// when this backend/format pair cannot dispatch [YuvOperation.convert], and
  /// [YuvNativeException] for a native overflow/allocation/internal failure.
  YuvImage applyRgbaBytes(Uint8List bytes) => throw UnimplementedError();

  /// Converts this image to grayscale in place and returns `this`.
  YuvImage applyGrayscale() => throw UnimplementedError();

  /// Applies a black/white threshold effect in place and returns `this`.
  YuvImage applyBlackWhite() => throw UnimplementedError();

  /// Inverts visible colors in place and returns `this`.
  YuvImage applyNegate() => throw UnimplementedError();

  /// Applies a Gaussian-weighted blur in place and returns `this`.
  ///
  /// [radius] `0` is a no-op. [sigma] must be finite and positive for a
  /// non-zero [radius].
  YuvImage applyGaussianBlur({required int radius, required double sigma}) => throw UnimplementedError();

  /// Applies a uniform mean blur in place and returns `this`.
  ///
  /// [region] uses image-pixel coordinates, rounded outward to whole pixels
  /// and clamped to the image bounds; `null` blurs the whole frame. [radius]
  /// `0` is a no-op.
  YuvImage applyMeanBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  /// Applies a normalized box blur in place and returns `this`.
  ///
  /// [region] uses image-pixel coordinates, rounded outward to whole pixels
  /// and clamped to the image bounds; `null` blurs the whole frame. [radius]
  /// `0` is a no-op.
  YuvImage applyBoxBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  /// Crops this image to [region] in place and returns `this`.
  ///
  /// [region] uses image-pixel coordinates. Its near edges are rounded down,
  /// far edges are rounded up, and the result is clamped to the image bounds.
  /// An empty effective region is a no-op.
  YuvImage applyCrop(ui.Rect region) => throw UnimplementedError();

  /// Flips this image horizontally in place and returns `this`.
  YuvImage applyFlipHorizontal() => throw UnimplementedError();

  /// Flips this image vertically in place and returns `this`.
  YuvImage applyFlipVertical() => throw UnimplementedError();

  /// Rotates this image in place and returns `this`.
  ///
  /// [YuvImageRotation.rotation0] is a no-op.
  YuvImage applyRotation(YuvImageRotation rotation) => throw UnimplementedError();

  /// Converts this image to [format] in place and returns `this`.
  ///
  /// Converting to the format this image already has is a no-op.
  YuvImage applyFormat(YuvPixelFormat format) => throw UnimplementedError();

  /// Swaps every interleaved U/V sample value of this NV12 image in place,
  /// keeping the frame labeled NV12, and returns `this`.
  ///
  /// This is a visible channel-value effect, not a format conversion (section
  /// 14, Q1). Throws [UnsupportedError] for I420/BGRA8888 without converting
  /// or mutating.
  YuvImage applyChromaSwap() => throw UnimplementedError();

  /// Returns a new, independent image cropped to [region].
  ///
  /// This image (bytes and revision) is left unchanged. An empty effective
  /// region still returns a new, independently owned image rather than
  /// aliasing this one.
  YuvImage cropped(ui.Rect region) => throw UnimplementedError();

  /// Returns a new, independent image rotated by [rotation].
  ///
  /// This image (bytes and revision) is left unchanged, even for
  /// [YuvImageRotation.rotation0].
  YuvImage rotated(YuvImageRotation rotation) => throw UnimplementedError();

  /// Returns a new, independent image converted to I420.
  YuvImage toI420() => throw UnimplementedError();

  /// Returns a new, independent image converted to NV12.
  YuvImage toNv12() => throw UnimplementedError();

  /// Returns a new, independent image converted to BGRA8888.
  YuvImage toBgra() => throw UnimplementedError();

  /// Returns every plane's full `height * rowStride` storage concatenated in
  /// format order, including declared row/pixel padding.
  Uint8List toBytes() => throw UnimplementedError();

  /// Returns exactly `width * height * 4` tightly packed visible BGRA8888
  /// pixels.
  Uint8List toBgraBytes() => throw UnimplementedError();
}
