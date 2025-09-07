import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/src/functions/bgra8888.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

class YuvImageWidget extends StatefulWidget {
  final YuvImage image;
  final WidgetBuilder? onPrepare;
  final BoxFit boxFit;

  const YuvImageWidget({
    super.key,
    required this.image,
    this.onPrepare,
    this.boxFit = BoxFit.none,
  });

  @override
  State<YuvImageWidget> createState() => _YuvImageWidgetState();
}

class _YuvImageWidgetState extends State<YuvImageWidget> {
  late YuvImageProvider _provider;

  @override
  void initState() {
    _provider = YuvImageProvider(width: widget.image.width, height: widget.image.height);
    _provider.update(widget.image.toBgra8888());
    super.initState();
  }

  @override
  void didUpdateWidget(covariant YuvImageWidget oldWidget) {
    _provider.update(widget.image.toBgra8888());
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: _provider,
      gaplessPlayback: true,
      width: widget.image.width.toDouble(),
      height: widget.image.height.toDouble(),
      fit: widget.boxFit,
    );
  }
}

class YuvImageProvider extends ImageProvider<YuvImageProvider> {
  final int width;
  final int height;
  final ui.PixelFormat pixelFormat;

  final _completer = YuvImageStreamCompleter();

  YuvImageProvider({
    required this.width,
    required this.height,
    this.pixelFormat = ui.PixelFormat.bgra8888,
  });

  void update(Uint8List bytes) => _completer.update(bytes, width, height, pixelFormat);

  @override
  Future<YuvImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(YuvImageProvider key, ImageDecoderCallback decode) => _completer;
}

class YuvImageStreamCompleter extends ImageStreamCompleter {
  void update(Uint8List bytes, int width, int height, ui.PixelFormat format) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: format);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    setImage(ImageInfo(image: frame.image));
  }
}
