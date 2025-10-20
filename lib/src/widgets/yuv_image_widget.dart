import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

class YuvImageWidget extends StatelessWidget {
  final YuvImage image;
  final BoxFit boxFit;
  final ImageLoadingBuilder? loadingBuilder;

  const YuvImageWidget({
    super.key,
    required this.image,
    this.loadingBuilder,
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
    );
  }
}

class YuvImageProvider extends ImageProvider<YuvImageProvider> {
  final YuvImage image;

  YuvImageProvider(this.image);

  @override
  Future<YuvImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(YuvImageProvider key, ImageDecoderCallback decode) {
    final streamController = StreamController<ImageChunkEvent>();
    final codecCompleter = Completer<ui.Codec>();

    _loadAsync(key, decode, streamController, codecCompleter).catchError((ex, stack) {
      PaintingBinding.instance.imageCache.evict(key);
    });

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
    chunkStream.add(ImageChunkEvent(cumulativeBytesLoaded: 0, expectedTotalBytes: image.width * image.height * image.y.pixelStride));
    final bytes = image.toBgra8888();
    final descriptor = ui.ImageDescriptor.raw(await ui.ImmutableBuffer.fromUint8List(bytes),
        width: image.width, height: image.height, pixelFormat: ui.PixelFormat.bgra8888);
    final codec = await descriptor.instantiateCodec();
    // final frame = await codec.getNextFrame();
    // final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    chunkStream.add(ImageChunkEvent(cumulativeBytesLoaded: bytes.length, expectedTotalBytes: bytes.length));
    codecCompleter.complete(codec);
    await chunkStream.close();
  }
}
