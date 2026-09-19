import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Flutter widget that renders a [YuvImage].
class YuvImageWidget extends StatelessWidget {
  /// Source image.
  final YuvImage image;

  /// Image fit behavior.
  final BoxFit boxFit;

  /// Optional loading builder delegated to [Image].
  final ImageLoadingBuilder? loadingBuilder;

  /// Optional error builder delegated to [Image].
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Optional frame builder delegated to [Image].
  final ImageFrameBuilder? frameBuilder;

  /// Creates a widget that renders [image] as a Flutter [Image].
  ///
  /// [boxFit] controls layout fitting behavior.
  /// Builder callbacks are forwarded to the underlying [Image] widget.
  const YuvImageWidget({super.key, required this.image, this.loadingBuilder, this.errorBuilder, this.frameBuilder, this.boxFit = BoxFit.none});

  @override
  Widget build(BuildContext context) {
    return Image(
      image: YuvImageProvider(image),
      gaplessPlayback: true,
      width: image.width.toDouble(),
      height: image.height.toDouble(),
      fit: boxFit,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      frameBuilder: frameBuilder,
    );
  }
}

/// [ImageProvider] implementation backed by a [YuvImage].
///
/// Converts source frame to tightly packed BGRA8888 bytes and decodes it into
/// a single-frame [ui.Image].
///
/// A [YuvImage] is mutable in place, so neither the instance nor its content
/// alone identifies a frame. For this package's own backends the cache key is
/// therefore the pair of the image identity and the revision observed when this
/// provider was created: rebuilding around an untouched image reuses the decoded
/// frame, while any mutation produces a different key and a fresh decode.
///
/// A foreign `implements YuvImage` gets the pre-0.2.5 behaviour instead — every
/// provider is a distinct key, so every rebuild re-converts. Such a class
/// predates the revision seam and mutates without reporting it, so treating its
/// unchanged revision as proof of an unchanged frame would serve a stale image.
/// Re-converting is a cost; showing the wrong frame is a defect, and only the
/// cost is acceptable to trade in a patch release.
class YuvImageProvider extends ImageProvider<YuvImageProvider> {
  /// Source image.
  final YuvImage image;

  /// Revision of [image] captured when this provider was created, or `null`
  /// when [image] does not report its own mutations.
  ///
  /// The snapshot is deliberately immutable. Reading the live revision here
  /// would change the [hashCode] of a key already stored in the image cache,
  /// which would strand that entry and leak it.
  final int? _revision;

  /// Creates an image provider for [image].
  YuvImageProvider(this.image) : _revision = YuvRevision.tracksOwnMutations(image) ? YuvRevision.revisionOf(image) : null;

  @override
  Future<YuvImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    // A null snapshot means the image does not report its mutations, so no two
    // providers over it can be proven to describe the same frame.
    if (_revision == null) {
      return false;
    }
    return other is YuvImageProvider && identical(image, other.image) && _revision == other._revision;
  }

  // Plane content is deliberately not hashed: a full frame hash on every
  // rebuild would cost more than the conversion this cache key exists to avoid.
  // An untracked image falls back to identity, matching its always-miss equality.
  @override
  int get hashCode => _revision == null ? identityHashCode(this) : Object.hash(identityHashCode(image), _revision);

  @override
  ImageStreamCompleter loadImage(YuvImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_loadImageFrame(key));
  }

  Future<ImageInfo> _loadImageFrame(YuvImageProvider key) async {
    const bytesPerPixel = 4;
    final expectedTotalBytes = image.width * image.height * bytesPerPixel;
    try {
      // Allow one frame so placeholder can render before CPU-heavy conversion.
      await Future<void>.delayed(Duration.zero);
      final bytes = image.toBgra8888();
      if (bytes.length != expectedTotalBytes) {
        throw StateError(
          'Invalid BGRA buffer size: got ${bytes.length}, expected $expectedTotalBytes '
          'for ${image.width}x${image.height}',
        );
      }
      final imageCompleter = Completer<ui.Image>();
      ui.decodeImageFromPixels(bytes, image.width, image.height, ui.PixelFormat.bgra8888, imageCompleter.complete);
      final decoded = await imageCompleter.future;
      return ImageInfo(image: decoded, scale: 1.0);
    } catch (ex, stack) {
      PaintingBinding.instance.imageCache.evict(key);
      Error.throwWithStackTrace(ex, stack);
    }
  }
}
