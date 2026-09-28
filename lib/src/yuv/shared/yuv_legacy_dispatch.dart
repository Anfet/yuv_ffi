import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Internal dispatch interface for deprecated [DeprecatedYuvImageApi] methods.
///
/// Package backends implement this adapter so legacy operations can preserve
/// argument validation and native error behavior without repeating capability
/// checks. When a `YuvImage` implementation does not provide this adapter,
/// deprecated methods use their public `apply*` methods where possible.
///
/// `swapNv()` requires atomic state replacement. It throws [UnsupportedError]
/// without mutating when a foreign implementation cannot provide that adapter.
abstract interface class YuvLegacyDispatchAdapter {
  /// Applies the black and white effect in place without checking capabilities.
  YuvImage legacyBlackWhite();

  /// Applies grayscale in place without checking capabilities.
  YuvImage legacyGrayscale();

  /// Applies color negation in place without checking capabilities.
  YuvImage legacyNegate();

  /// Applies Gaussian blur in place without checking capabilities.
  ///
  /// Validates [radius] and [sigma]. A zero [radius] is a no-op.
  YuvImage legacyGaussianBlur({required int radius, required double sigma});

  /// Applies box blur in place without checking capabilities.
  ///
  /// Validates [radius]. A zero [radius] or empty [rect] is a no-op.
  YuvImage legacyBoxBlur({required int radius, ui.Rect? rect});

  /// Applies mean blur in place with the validation and no-op behavior of
  /// [legacyBoxBlur].
  YuvImage legacyMeanBlur({required int radius, ui.Rect? rect});

  /// Crops the image in place without checking capabilities. An empty
  /// effective crop area is a no-op.
  YuvImage legacyCrop(ui.Rect rect);

  /// Flips the image horizontally in place without checking capabilities.
  YuvImage legacyFlipHorizontal();

  /// Flips the image vertically in place without checking capabilities.
  YuvImage legacyFlipVertical();

  /// Rotates the image in place without checking capabilities.
  /// [YuvImageRotation.rotation0] is a no-op.
  YuvImage legacyRotate(YuvImageRotation rotation);

  /// Replaces the image pixels from RGBA8888 [bytes] in place without checking
  /// capabilities. Validates the exact byte length.
  void legacyFromRgba8888(Uint8List bytes);

  /// Converts the image to [target] in place without checking capabilities.
  /// Returns the receiver; converting to its current format is a no-op.
  // ignore: deprecated_member_use_from_same_package
  YuvImage legacyConvertTo(YuvFileFormat target);

  /// Converts this image to canonical NV12 storage first if it is not
  /// already NV12, then swaps every interleaved U/V sample value in place,
  /// and returns `this`.
  ///
  /// Converts to NV12 if needed, then swaps every interleaved U/V sample in
  /// one atomic in-place update. Returns the receiver.
  YuvImage legacySwapNv();

  /// Decodes [stream] and atomically replaces the image's format, geometry,
  /// and planes.
  ///
  /// Decoding completes into a fully validated draft (`YuvCodec.decodeStream`)
  /// before anything on this receiver is touched, so a malformed payload
  /// throws [FormatException] and leaves format, geometry, planes and revision
  /// exactly as they were. On success, the revision advances exactly once.
  ///
  /// A foreign `YuvImage` implementation cannot provide this replacement
  /// through its `apply*` methods, so [DeprecatedYuvImageApi.load] throws
  /// [UnsupportedError] without mutating when the receiver lacks this adapter.
  Future<void> legacyLoad(Stream<List<int>> stream);
}
