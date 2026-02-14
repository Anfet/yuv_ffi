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

  const YuvImageWidget({
    super.key,
    required this.image,
    this.loadingBuilder,
    this.errorBuilder,
    this.frameBuilder,
    this.boxFit = BoxFit.none,
  });

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

class YuvImageProvider extends ImageProvider<YuvImageProvider> {
  /// Source image.
  final YuvImage image;

  /// Creates an image provider for [image].
  YuvImageProvider(this.image);

  @override
  Future<YuvImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      YuvImageProvider key, ImageDecoderCallback decode) {
    final streamController = StreamController<ImageChunkEvent>();
    final codecCompleter = Completer<ui.Codec>();

    _loadAsync(key, decode, streamController, codecCompleter);

    return MultiFrameImageStreamCompleter(
      codec: codecCompleter.future,
      scale: 1.0,
      chunkEvents: streamController.stream,
    );
  }

  Future<void> _loadAsync(
    YuvImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkStream,
    Completer<ui.Codec> codecCompleter,
  ) async {
    const bytesPerPixel = 4;
    final expectedTotalBytes = image.width * image.height * bytesPerPixel;
    ui.ImageDescriptor? descriptor;
    try {
      chunkStream.add(
        ImageChunkEvent(
          cumulativeBytesLoaded: 0,
          expectedTotalBytes: expectedTotalBytes,
        ),
      );
      // Allow one frame so placeholder can render before CPU-heavy conversion.
      await Future<void>.delayed(Duration.zero);
      final bytes = image.toBgra8888();
      descriptor = ui.ImageDescriptor.raw(
        await ui.ImmutableBuffer.fromUint8List(bytes),
        width: image.width,
        height: image.height,
        pixelFormat: ui.PixelFormat.bgra8888,
      );
      final codec = await descriptor.instantiateCodec();
      chunkStream.add(
        ImageChunkEvent(
          cumulativeBytesLoaded: bytes.length,
          expectedTotalBytes: bytes.length,
        ),
      );
      if (!codecCompleter.isCompleted) {
        codecCompleter.complete(codec);
      }
    } catch (ex, stack) {
      PaintingBinding.instance.imageCache.evict(key);
      if (!codecCompleter.isCompleted) {
        codecCompleter.completeError(ex, stack);
      }
    } finally {
      descriptor?.dispose();
      if (!chunkStream.isClosed) {
        await chunkStream.close();
      }
    }
  }
}
