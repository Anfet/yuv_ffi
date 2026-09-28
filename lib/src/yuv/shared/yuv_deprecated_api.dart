import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Uint8List;

import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_legacy_dispatch.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_pixel_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_plane.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Deprecated instance methods that forward to the current [YuvImage] API.
///
/// Package backends use their package-private legacy dispatch adapter.
/// Foreign implementations use their current public methods where possible.
/// [swapNv] and [load] throw [UnsupportedError] for a foreign implementation
/// because their changes cannot be staged through the public API.
extension DeprecatedYuvImageApi on YuvImage {
  /// Alias for [yPlane]. Never null: every format has a Y plane.
  @Deprecated('Use yPlane.')
  YuvPlane get y => yPlane;

  /// The U plane for planar formats, or the interleaved UV/VU plane for
  /// semi-planar ones. `null` for a format with only one plane (BGRA8888).
  @Deprecated('Use uPlane. Throws StateError instead of returning null when this format has no U plane.')
  YuvPlane? get u => planes.length > 1 ? planes[1] : null;

  /// The V plane for planar formats. `null` for a format with fewer than
  /// three planes.
  @Deprecated('Use vPlane. Throws StateError instead of returning null when this format has no V plane.')
  YuvPlane? get v => planes.length > 2 ? planes[2] : null;

  /// Returns all planes concatenated into a single byte buffer.
  @Deprecated('Use toBytes().')
  Uint8List getBytes() => toBytes();

  /// Returns BGRA8888 bytes with tightly packed rows.
  ///
  /// Returned length is always `width * height * 4`.
  @Deprecated('Use toBgraBytes().')
  Uint8List toBgra8888() => toBgraBytes();

  /// Applies a black/white threshold effect in-place and returns `this`.
  @Deprecated('Use applyBlackWhite().')
  YuvImage blackwhite() {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyBlackWhite() : applyBlackWhite();
  }

  /// Applies Gaussian blur in-place and returns `this`.
  @Deprecated('Use applyGaussianBlur().')
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) {
    final adapter = _adapter();
    return adapter != null
        ? adapter.legacyGaussianBlur(radius: radius, sigma: sigma.toDouble())
        : applyGaussianBlur(radius: radius, sigma: sigma.toDouble());
  }

  /// Applies box blur in-place and returns `this`.
  @Deprecated('Use applyBoxBlur().')
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyBoxBlur(radius: radius, rect: rect) : applyBoxBlur(radius: radius, region: rect);
  }

  /// Applies mean blur in-place and returns `this`.
  @Deprecated('Use applyMeanBlur().')
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyMeanBlur(radius: radius, rect: rect) : applyMeanBlur(radius: radius, region: rect);
  }

  /// Converts non-NV12 input to canonical NV12 storage first, then swaps
  /// every interleaved U/V sample value in place, and returns `this`.
  ///
  /// This is a two-step legacy path, not a simple alias for
  /// [YuvImage.applyChromaSwap].
  ///
  /// Unlike every other member of this extension, this one has no
  /// public-`apply*`-based fallback for a foreign `implements YuvImage`: the
  /// convert-then-swap sequence must publish only once, after both steps have
  /// succeeded, and a foreign receiver
  /// exposes no way to stage that atomically. Throws [UnsupportedError]
  /// without mutating for a receiver that does not implement
  /// the package-private legacy dispatch adapter.
  @Deprecated(
    'Use applyFormat(YuvPixelFormat.nv12) followed by applyChromaSwap() if a two-step conversion is intended, '
    'or applyChromaSwap() directly on an image already in NV12.',
  )
  YuvImage swapNv() {
    final Object self = this;
    if (self is YuvLegacyDispatchAdapter) {
      return self.legacySwapNv();
    }
    throw UnsupportedError('swapNv() requires this package\'s own YuvImage backend to stage its atomic convert-then-swap.');
  }

  /// Converts image to NV21-labeled representation in-place and returns
  /// `this`.
  @Deprecated('Use toNv12() or applyFormat(YuvPixelFormat.nv12).')
  YuvImage toYuvNv21() {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyConvertTo(YuvFileFormat.nv21) : applyFormat(YuvPixelFormat.nv12);
  }

  /// Converts image to I420 representation in-place and returns `this`.
  @Deprecated('Use toI420() or applyFormat(YuvPixelFormat.i420).')
  YuvImage toYuvI420() {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyConvertTo(YuvFileFormat.i420) : applyFormat(YuvPixelFormat.i420);
  }

  /// Converts image to BGRA8888 representation in-place and returns `this`.
  @Deprecated('Use toBgra() or applyFormat(YuvPixelFormat.bgra8888).')
  YuvImage toYuvBgra8888() {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyConvertTo(YuvFileFormat.bgra8888) : applyFormat(YuvPixelFormat.bgra8888);
  }

  /// Crops the image to [rect] in-place and returns `this`.
  @Deprecated('Use applyCrop().')
  YuvImage crop(ui.Rect rect) {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyCrop(rect) : applyCrop(rect);
  }

  /// Flips the image horizontally in-place and returns `this`.
  @Deprecated('Use applyFlipHorizontal().')
  YuvImage flipHorizontally() {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyFlipHorizontal() : applyFlipHorizontal();
  }

  /// Flips the image vertically in-place and returns `this`.
  @Deprecated('Use applyFlipVertical().')
  YuvImage flipVertically() {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyFlipVertical() : applyFlipVertical();
  }

  /// Fills this image from RGBA8888 bytes.
  @Deprecated('Use applyRgbaBytes().')
  void fromRgba8888(Uint8List bytes) {
    final adapter = _adapter();
    if (adapter != null) {
      adapter.legacyFromRgba8888(bytes);
    } else {
      applyRgbaBytes(bytes);
    }
  }

  /// Converts image to grayscale in-place and returns `this`.
  @Deprecated('Use applyGrayscale().')
  YuvImage grayscale() {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyGrayscale() : applyGrayscale();
  }

  /// Inverts colors in-place and returns `this`.
  @Deprecated('Use applyNegate().')
  YuvImage negate() {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyNegate() : applyNegate();
  }

  /// Rotates image in-place and returns `this`.
  @Deprecated('Use applyRotation().')
  YuvImage rotate(YuvImageRotation rotation) {
    final adapter = _adapter();
    return adapter != null ? adapter.legacyRotate(rotation) : applyRotation(rotation);
  }

  /// Serializes this image into [sink].
  ///
  /// Forwards to [YuvImage.encodeTo] with identical bytes; does not mutate.
  @Deprecated('Use encodeTo().')
  Future<void> save(Sink<List<int>> sink) => encodeTo(sink);

  /// Decodes [stream] and replaces this image's format, geometry and planes
  /// in place.
  ///
  /// The adapter replaces the full state atomically, as [swapNv] does. A
  /// foreign `implements YuvImage` that does not provide it throws
  /// [UnsupportedError] without mutating the receiver -- there is no
  /// `apply*`-based fallback for a full state replacement. Use the static
  /// [YuvImage.decode] to create a new image instead.
  @Deprecated('Use the static YuvImage.decode().')
  Future<void> load(Stream<List<int>> stream) {
    final Object self = this;
    if (self is YuvLegacyDispatchAdapter) {
      return self.legacyLoad(stream);
    }
    throw UnsupportedError('load() requires this package\'s own YuvImage backend to stage its atomic state replacement.');
  }

  /// This receiver as its package-private legacy dispatch adapter, or `null`
  /// for a foreign `implements YuvImage` that does not provide one.
  YuvLegacyDispatchAdapter? _adapter() {
    final Object self = this;
    return self is YuvLegacyDispatchAdapter ? self : null;
  }
}
