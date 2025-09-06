import 'dart:ui' show ClipOp;

import 'package:flutter/material.dart';
import 'package:yuv_ffi_example/widgets/crop_targets.dart';

sealed class ShadeWidget implements Widget {
  factory ShadeWidget.oval({required CropTarget target}) => _OvalShades(target: target);

  factory ShadeWidget.rect({required CropTarget target}) => _RectShade(target: target);
}

/// Оверлей с затенением экрана и овальным «окном» по Rect из CropTarget.place(size).
class _OvalShades extends StatelessWidget implements ShadeWidget {
  final CropTarget target;

  /// Цвет тени (поверх всего за вычетом окна)
  final Color shadeColor;

  /// Толщина рамки вокруг овала (0 — без рамки)
  final double borderWidth;

  /// Цвет рамки овала
  final Color borderColor;

  /// Показывать ли вспомогательные крест-гайды по центру овала
  final bool showGuides;

  const _OvalShades({
    super.key,
    required this.target,
    this.shadeColor = const Color(0x99000000),
    this.borderWidth = 0,
    this.borderColor = Colors.white,
    this.showGuides = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OvalShadesPainter(target: target, shadeColor: shadeColor, borderWidth: borderWidth, borderColor: borderColor, showGuides: showGuides),
    );
  }
}

class _OvalShadesPainter extends CustomPainter {
  final CropTarget target;
  final Color shadeColor;
  final double borderWidth;
  final Color borderColor;
  final bool showGuides;

  _OvalShadesPainter({
    required this.target,
    required this.shadeColor,
    required this.borderWidth,
    required this.borderColor,
    required this.showGuides,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1) прямоугольник овального окна по твоей логике
    final rect = target.place(size);

    // 2) полный экран как Path
    final full = Path()..addRect(Offset.zero & size);

    // 3) овальное окно
    final hole = Path()..addOval(rect);

    // 4) рисуем тень как «экран минус овал»
    final diff = Path.combine(PathOperation.difference, full, hole);
    final paintShade = Paint()
      ..color = shadeColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(diff, paintShade);

    // 5) рамка овала (опционально)
    if (borderWidth > 0) {
      final border = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..isAntiAlias = true;
      canvas.drawOval(rect, border);
    }

    // 6) вспомогательные линии (опционально)
    if (showGuides) {
      final g = Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..isAntiAlias = true;
      canvas.drawLine(rect.centerLeft, rect.centerRight, g);
      canvas.drawLine(rect.topCenter, rect.bottomCenter, g);
    }
  }

  @override
  bool shouldRepaint(covariant _OvalShadesPainter old) {
    return old.target != target ||
        old.shadeColor != shadeColor ||
        old.borderWidth != borderWidth ||
        old.borderColor != borderColor ||
        old.showGuides != showGuides;
  }
}

class _RectShade extends StatelessWidget implements ShadeWidget {
  final CropTarget target;

  const _RectShade({Key? key, required this.target}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return CustomPaint(size: Size(width, height), painter: _RectShadesPainter(target));
  }
}

class _RectShadesPainter extends CustomPainter {
  final CropTarget target;

  _RectShadesPainter(this.target);

  final Paint backgroundPaint = Paint()..color = const Color(0x80000000);
  final Paint linePaint = Paint()
    ..color = Colors.red
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = target.place(size);

    canvas.drawLine(rect.topCenter, rect.bottomCenter, linePaint);
    canvas.drawLine(rect.centerLeft, rect.centerRight, linePaint);
    // logMessage("new shades positioned at $rect");
    canvas.clipRect(rect, clipOp: ClipOp.difference);
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, size.height), backgroundPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
