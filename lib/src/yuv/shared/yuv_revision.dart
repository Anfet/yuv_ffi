import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Implemented by this package's backends to report their own revision.
///
/// A [YuvImage] is mutable in place, so neither the instance nor its content
/// alone identifies a frame: an in-place operation keeps the same object while
/// replacing what it holds. A monotonic revision closes that gap and is what
/// makes the image usable as an image-cache key.
///
/// The revision deliberately lives here rather than on the public [YuvImage]
/// interface. Adding required members to an `abstract interface class` breaks
/// every external `implements YuvImage` on a patch update, so this package's
/// own backends expose it through this interface while a foreign implementation
/// is tracked externally through an [Expando]. Both are invisible to callers:
/// [YuvRevision] and the public [YuvImageInvalidation] extension work for
/// either kind.
///
/// This type is not exported from `yuv_ffi.dart`, so an external implementation
/// never has to know it exists.
abstract interface class YuvRevisionAware {
  /// Monotonic counter identifying the current frame content.
  int get internalRevision;

  /// Advances [internalRevision] by one.
  void bumpInternalRevision();
}

/// Revisions for images that do not implement [YuvRevisionAware].
///
/// An [Expando] holds the value beside the object without touching its type, so
/// a foreign `implements YuvImage` still participates in cache invalidation.
final Expando<int> _foreignRevisions = Expando<int>('yuv_ffi.revision');

/// Reads and advances the revision of any [YuvImage].
abstract final class YuvRevision {
  /// Current revision of [image].
  ///
  /// Returns zero for an image that has never been marked dirty and does not
  /// track a revision itself.
  static int revisionOf(YuvImage image) {
    final Object candidate = image;
    if (candidate is YuvRevisionAware) {
      return candidate.internalRevision;
    }
    return _foreignRevisions[image] ?? 0;
  }

  /// Advances the revision of [image] by one.
  static void bump(YuvImage image) {
    final Object candidate = image;
    if (candidate is YuvRevisionAware) {
      candidate.bumpInternalRevision();
      return;
    }
    _foreignRevisions[image] = (_foreignRevisions[image] ?? 0) + 1;
  }
}

/// Revision access and manual cache invalidation for a [YuvImage].
///
/// An extension rather than interface members, so adding it does not break an
/// existing external implementation.
extension YuvImageInvalidation on YuvImage {
  /// Monotonic counter identifying the current frame content.
  ///
  /// Every successful mutating operation advances it exactly once. Operations
  /// that genuinely change nothing — rotating by zero, an empty crop, or
  /// converting to the format the image already has — leave it untouched.
  ///
  /// Direct writes through the mutable plane API are invisible here and need an
  /// explicit [markDirty] call.
  int get revision => YuvRevision.revisionOf(this);

  /// Signals that plane content was modified through the mutable plane API.
  ///
  /// Writing straight into `YuvPlane.bytes` (or calling `setPixel` and
  /// `assignFrom`) cannot be intercepted, so such changes do not advance
  /// [revision] on their own. Call this afterwards, or a widget may keep
  /// showing the previous frame from the image cache:
  ///
  /// ```dart
  /// image.yPlane.bytes[0] = 0xFF;
  /// image.markDirty();
  /// ```
  ///
  /// Calling it when nothing changed is harmless: it only costs a cache miss.
  void markDirty() => YuvRevision.bump(this);
}
