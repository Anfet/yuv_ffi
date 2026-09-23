import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yuv_ffi/src/yuv/shared/yuv_file_format.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Implemented by this package's backends to give the deprecated `0.3.0`
/// instance methods in [DeprecatedYuvImageApi] their historical,
/// capability-ungated dispatch (`doc/api-abi-0.4-design.md` sections 4, 8,
/// 14 Q1).
///
/// The `0.4.0` `apply*` surface added a precondition `0.3.0` never had: every
/// `apply*` calls `yuvRequireCapability` first and throws `UnsupportedError`
/// before `YuvFfi.initialize()` has completed (REL-04's post-REL-09
/// addendum). A deprecated method that simply forwarded to its `apply*`
/// replacement would inherit that gate and change observable `0.3.0`
/// behavior for existing callers -- confirmed by several pre-REL-06 tests
/// (`bgra_mean_blur_contract_test.dart`'s "an invalid radius is rejected
/// before reaching native code", `conversions_test.dart`'s "fromRgba8888
/// validates input length", `io_abi_v1_public_contract_test.dart`'s
/// non-zero-status group) that call these methods with no prior
/// `YuvFfi.initialize()` and expect argument validation or a native-status
/// exception, not `UnsupportedError`. This interface is the same
/// capability-ungated dispatch path the corresponding `apply*` method calls
/// internally (`_blur`, `_convertTo`, `_crop`, and so on on each backend),
/// exposed under one name so the deprecated extension can reach it without
/// going through the capability gate a second time.
///
/// Not exported from `yuv_ffi.dart`, the same way [YuvRevisionAware] is not: a
/// foreign `implements YuvImage` never has to know it exists. For every method
/// here except [legacySwapNv], [DeprecatedYuvImageApi] falls back to the
/// receiver's own public `apply*`/`applyFormat` method when it does not
/// implement this adapter -- REL-04's already-accepted breaking change
/// requires every `YuvImage` implementer to provide those, so a foreign
/// receiver still gets a working (capability-gated) deprecated method rather
/// than an outright failure. [legacySwapNv] is the one exception: its
/// two-step convert-then-swap cannot be made atomic against an arbitrary
/// foreign implementation, so [DeprecatedYuvImageApi.swapNv] throws
/// [UnsupportedError] without mutating when the receiver does not implement
/// this adapter, the same fallback section 8 documents for the legacy
/// `load()` extension when a foreign implementation cannot provide its own
/// atomic state-replacement adapter.
abstract interface class YuvLegacyDispatchAdapter {
  /// `0.3.0` `blackwhite()`: in-place, no capability gate.
  YuvImage legacyBlackWhite();

  /// `0.3.0` `grayscale()`: in-place, no capability gate.
  YuvImage legacyGrayscale();

  /// `0.3.0` `negate()`: in-place, no capability gate.
  YuvImage legacyNegate();

  /// `0.3.0` `gaussianBlur(radius:, sigma:)`: validates [radius] and [sigma]
  /// and short-circuits on `radius == 0`, exactly as `0.3.0` did, with no
  /// capability gate.
  YuvImage legacyGaussianBlur({required int radius, required double sigma});

  /// `0.3.0` `boxBlur(radius:, rect:)`: validates [radius] and short-circuits
  /// on `radius == 0` or an empty [rect], with no capability gate.
  YuvImage legacyBoxBlur({required int radius, ui.Rect? rect});

  /// `0.3.0` `meanBlur(radius:, rect:)`: same contract as [legacyBoxBlur].
  YuvImage legacyMeanBlur({required int radius, ui.Rect? rect});

  /// `0.3.0` `crop(rect)`: in-place, no capability gate. An empty effective
  /// crop area is a no-op.
  YuvImage legacyCrop(ui.Rect rect);

  /// `0.3.0` `flipHorizontally()`: in-place, no capability gate.
  YuvImage legacyFlipHorizontal();

  /// `0.3.0` `flipVertically()`: in-place, no capability gate.
  YuvImage legacyFlipVertical();

  /// `0.3.0` `rotate(rotation)`: in-place, no capability gate.
  /// `YuvImageRotation.rotation0` is a no-op.
  YuvImage legacyRotate(YuvImageRotation rotation);

  /// `0.3.0` `fromRgba8888(bytes)`: validates [bytes]' exact length and
  /// mutates in place, with no capability gate.
  void legacyFromRgba8888(Uint8List bytes);

  /// `0.3.0` `toYuvI420()`/`toYuvBgra8888()`/`toYuvNv21()`: converts this
  /// image to [target] in place and returns `this`; a conversion to the
  /// format this image already has is a no-op. No capability gate.
  YuvImage legacyConvertTo(YuvFileFormat target);

  /// Converts this image to canonical NV12 storage first if it is not
  /// already NV12, then swaps every interleaved U/V sample value in place,
  /// and returns `this`.
  ///
  /// `swapNv()` cannot be expressed as a plain `extension on YuvImage` built
  /// out of `applyFormat()` followed by `applyChromaSwap()`: the first call
  /// would publish the NV12 conversion and bump the revision before the swap
  /// was even attempted, so a chroma swap that then failed would leave the
  /// receiver visibly half-migrated -- exactly the partial mutation section
  /// 13's transactional design forbids for every mutating operation,
  /// deprecated or not. Each backend already stages both steps as local
  /// drafts and publishes once, so this method only exposes that existing
  /// atomic path under one name. Keeps the legacy `nv21`-labeled UV byte
  /// order and historical output bytes exactly as `0.3.0`'s `swapNv()`
  /// produced them.
  YuvImage legacySwapNv();

  /// `0.3.0` `load(stream)`: decodes [stream] and atomically replaces this
  /// image's format, geometry and planes with what it held.
  ///
  /// Decoding completes into a fully validated draft (`YuvCodec.decodeStream`)
  /// before anything on this receiver is touched, so a malformed payload
  /// throws [FormatException] and leaves format, geometry, planes and revision
  /// exactly as they were -- the same atomic state-replacement contract every
  /// backend's `YuvImageState.decodeAndReplace` already gives. On success the
  /// revision advances exactly once.
  ///
  /// Unlike every other method here, there is no `apply*`-based fallback a
  /// foreign `implements YuvImage` could be forwarded to: replacing format,
  /// geometry and every plane at once is not an operation the `0.4.0`
  /// interface exposes at all (`YuvImage.decode` builds a new instance
  /// instead), so `DeprecatedYuvImageApi.load` throws [UnsupportedError]
  /// without mutating when the receiver does not implement this adapter --
  /// exactly the fallback section 8 documents for legacy `load()`.
  Future<void> legacyLoad(Stream<List<int>> stream);
}
