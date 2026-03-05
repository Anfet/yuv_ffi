import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
class YuvImageProvider extends ImageProvider<YuvImageProvider> {
  /// Source image.
  final YuvImage image;

  /// Creates an image provider for [image].
  YuvImageProvider(this.image);

  @override
  Future<YuvImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

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
