import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:yuv_ffi/src/functions/bgra8888.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

class YuvImageWidget extends StatefulWidget {
  final YuvImage image;
  final WidgetBuilder? onPrepare;
  final bool displayDebugInfo;

  const YuvImageWidget({
    super.key,
    required this.image,
    this.onPrepare,
    this.displayDebugInfo = false,
  });

  @override
  State<YuvImageWidget> createState() => _YuvImageWidgetState();
}

class _YuvImageWidgetState extends State<YuvImageWidget> {
  ui.Image? image;

  @override
  void initState() {
    recodeSource();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant YuvImageWidget oldWidget) {
    recodeSource();
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    if (image == null) {
      return (widget.onPrepare ?? _defaultProgressBuilder).call(context);
    }

    return CustomPaint(
      size: Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
      painter: PixelPainter(image: image!, width: image!.width, height: image!.height),
    );
  }

  void recodeSource() {
    ui.decodeImageFromPixels(
      widget.image.toBgra8888(),
      widget.image.width,
      widget.image.height,
      ui.PixelFormat.bgra8888,
      (ui.Image img) => setState(() => image = img),
    );
  }

  Widget _defaultProgressBuilder(BuildContext context) => SizedBox();
}

class PixelPainter extends CustomPainter {
  final int width;
  final int height;
  final ui.Image image;

  PixelPainter({required this.image, required this.width, required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Rect.fromLTWH(0, 0, size.width, size.height), Paint());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      oldDelegate is PixelPainter && (width != oldDelegate.width || height != oldDelegate.height || image != oldDelegate.image);
}
