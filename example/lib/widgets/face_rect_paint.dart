import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

class FaceRectPainter extends CustomPainter {
  final YuvImage image;
  final Rect rect;
  final Color color;
  final double strokeWidth;

  FaceRectPainter({
    required this.image,
    required this.rect,
    this.color = Colors.green,
    this.strokeWidth = 2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rect = mapImageRectToWidget(
      imageRect: this.rect,
      imageSize: image.size,
      widgetSize: size,
      rotation: InputImageRotation.rotation0deg,
      mirrorHorizontally: true,
    );

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant FaceRectPainter old) {
    return true; //old.rect != rect || old.color != color || old.strokeWidth != strokeWidth;
  }

  Rect mapImageRectToWidget({
    required Rect imageRect, // face.boundingBox из ML Kit
    required Size imageSize, // Size(image.width, image.height) из CameraImage
    required Size widgetSize, // size из painter'а (CustomPainter.paint)
    required InputImageRotation rotation,
    required bool mirrorHorizontally, // фронталка: true
  }) {
    // 1) Учтём поворот 90/270: меняются оси
    final swapped = rotation == InputImageRotation.rotation90deg || rotation == InputImageRotation.rotation270deg;

    double imgW = swapped ? imageSize.height : imageSize.width;
    double imgH = swapped ? imageSize.width : imageSize.height;

    Rect r = imageRect;
    if (swapped) {
      // Повернём bbox в «прямые» координаты (origin в лев.верх)
      r = Rect.fromLTWH(
        imageRect.top,
        imgW - (imageRect.left + imageRect.width),
        imageRect.height,
        imageRect.width,
      );
    }

    // 2) Масштаб «как у CameraPreview (cover)» + центрирование
    final scale = (widgetSize.width / imgW > widgetSize.height / imgH) ? widgetSize.width / imgW : widgetSize.height / imgH;

    final dx = (widgetSize.width - imgW * scale) / 2.0;
    final dy = (widgetSize.height - imgH * scale) / 2.0;

    Rect out = Rect.fromLTWH(
      dx + r.left * scale,
      dy + r.top * scale,
      r.width * scale,
      r.height * scale,
    );

    // 3) Зеркалка для фронталки, чтобы совпасть с превью
    if (mirrorHorizontally) {
      out = Rect.fromLTWH(
        widgetSize.width - out.right,
        out.top,
        out.width,
        out.height,
      );
    }
    return out;
  }
}
