import 'dart:math';

import 'package:flutter/widgets.dart';

abstract class CropTarget {
  Rect place(Size size);

  factory CropTarget.precise(
    Size target, {
    Offset offset = Offset.zero,
    Alignment alignment = Alignment.topLeft,
  }) =>
      _CropTargetPrecise(target: target, offset: offset, alignment: alignment);

  factory CropTarget.percented({double left = 0.0, double top = 0.0, double right = 1.0, double bottom = 1.0}) =>
      _CropTargetPercented(left, top, right, bottom);

  factory CropTarget.squarePercented({double? px, double? py, Offset offset = Offset.zero}) => _CropTargetSquare(px, py, offset);

  factory CropTarget.fromRotation({required CropTarget source, int originalDegrees = 0}) => _CropRotator._(source, originalDegrees);
}

class _CropRotator implements CropTarget {
  final CropTarget source;
  final num degrees;

  _CropRotator._(this.source, this.degrees);

  @override
  Rect place(Size size) {
    ImageRotation rotation = ImageRotation.fromDegrees(degrees);
    if (rotation == ImageRotation.rotation0) {
      return source.place(size);
    }

    Size rotated = size.rotateBy(rotation);
    var rect = source.place(rotated);

    var w = rotated.width;
    var h = rotated.height;
    var cx = w ~/ 2;
    var cy = h ~/ 2;

    var lx = rect.left - cx;
    var ly = rect.top - cy;
    var rx = rect.right - cx;
    var ry = rect.bottom - cy;

    var l = rotation.applyTo(lx.toInt(), ly.toInt());
    var r = rotation.applyTo(rx.toInt(), ry.toInt());

    var cx1 = size.width ~/ 2;
    var cy1 = size.height ~/ 2;
    var lx1 = l[0] + cx1;
    var ly1 = l[1] + cy1;
    var rx1 = r[0] + cx1;
    var ry1 = r[1] + cy1;

    var lowx = min(lx1, rx1);
    var lowy = min(ly1, ry1);
    var highx = max(lx1, rx1);
    var highy = max(ly1, ry1);

    var result = Rect.fromLTRB(lowx.toDouble(), lowy.toDouble(), highx.toDouble(), highy.toDouble());
    return result;
  }
}

class _CropTargetSquare implements CropTarget {
  final double? px;
  final double? py;
  final Offset offset;

  _CropTargetSquare(this.px, this.py, this.offset);

  @override
  Rect place(Size size) {
    assert((px != null && py == null) || (px == null && py != null), "'px' or 'py' must be set but not both");

    assert(px == null || (px! >= 0.0 && px! <= 1.0), "'px' must be >= 0.0 and <= 1.0");
    assert(py == null || (py! >= 0.0 && py! <= 1.0), "'py' must be >= 0.0 and <= 1.0");
    assert(offset.dx >= 0.0 && offset.dy <= 1.0, "'offset'  must be >= 0.0 and <= 1.0");

    double width = 0.0;
    double height = 0.0;
    if (px != null) {
      width = size.width * px!;
      height = width;
    }

    if (py != null) {
      height = size.height * py!;
      width = height;
    }

    double dx = size.width * offset.dx;
    double dy = size.height * offset.dy;
    return Rect.fromLTRB(
        (size.width - width) / 2 + dx, (size.height - height) / 2 + dy, (size.width + width) / 2 + dx, (size.height + height) / 2 + dy);
  }
}

class _CropTargetPercented implements CropTarget {
  final double top;
  final double left;
  final double right;
  final double bottom;

  const _CropTargetPercented(this.left, this.top, this.right, this.bottom);

  @override
  Rect place(Size size) {
    assert(left >= 0.0 && left <= 1.0, "'left' must be between 0.0 and 1.0");
    assert(top >= 0.0 && top <= 1.0, "'top' must be between 0.0 and 1.0");
    assert(right >= 0.0 && right <= 1.0, "'right' must be between 0.0 and 1.0");
    assert(bottom >= 0.0 && bottom <= 1.0, "'bottom' must be between 0.0 and 1.0");

    double l = size.width * left;
    double t = size.height * top;
    double r = size.width * right;
    double b = size.height * bottom;

    return Rect.fromLTRB(l, t, r, b);
  }
}

class _CropTargetPrecise implements CropTarget {
  final Size target;
  final Offset offset;
  final Alignment alignment;

  const _CropTargetPrecise({
    required this.target,
    this.offset = Offset.zero,
    this.alignment = Alignment.topLeft,
  });

  @override
  Rect place(Size size) {
    double targetHalfWidth = target.width / 2;
    double targetHalfHeight = target.height / 2;

    double adjustedTop = targetHalfHeight;
    double adjustedLeft = targetHalfWidth;
    double yCenter = size.height / 2;
    double xCenter = size.width / 2;

    double yLength = yCenter - adjustedTop;
    double xLength = xCenter - adjustedLeft;

    double cy = yCenter + alignment.y * yLength;
    double cx = xCenter + alignment.x * xLength;

    double top = cy - targetHalfHeight;
    double bottom = cy + targetHalfHeight;
    double left = cx - targetHalfWidth;
    double right = cx + targetHalfWidth;

    return Rect.fromLTRB(left + offset.dx, top + offset.dy, right + offset.dx, bottom + offset.dy);
  }
}

extension SizeRotationExt on Size {
  Size rotateBy(ImageRotation rotation) {
    switch (rotation) {
      case ImageRotation.rotation0:
      case ImageRotation.rotation180:
        return this;
      case ImageRotation.rotation90:
      case ImageRotation.rotation270:
        return Size(height, width);
    }
  }
}

enum ImageRotation {
  rotation0(0),
  rotation90(90),
  rotation180(180),
  rotation270(270);

  final num degrees;

  const ImageRotation(this.degrees);

  ImageRotation get inverted {
    switch (this) {
      case ImageRotation.rotation0:
        return ImageRotation.rotation180;
      case ImageRotation.rotation90:
        return ImageRotation.rotation270;
      case ImageRotation.rotation180:
        return ImageRotation.rotation0;
      case ImageRotation.rotation270:
        return ImageRotation.rotation90;
    }
  }

  static ImageRotation fromDegrees(num degrees) {
    if (degrees < 0) {
      degrees = 360 - degrees.abs();
    }

    final num nangle = degrees % 360.0;
    if ((nangle % 90.0) != 0.0) {
      throw UnsupportedError("degrees must be dividable by 90");
    }

    final iangle = nangle ~/ 90.0;
    switch (iangle) {
      case 1:
        return ImageRotation.rotation90;
      case 2:
        return ImageRotation.rotation180;
      case 3:
        return ImageRotation.rotation270;
      default:
        return ImageRotation.rotation0;
    }
  }

  List<num> applyTo(num x, num y) {
    final matrix = transformMatrix();
    var a11 = matrix[0][0];
    var a12 = matrix[0][1];
    var a21 = matrix[1][0];
    var a22 = matrix[1][1];

    var x1 = a11 * x + a12 * y;
    var y1 = a21 * x + a22 * y;

    return [x1, y1];
  }

  List<List<int>> transformMatrix() {
    switch (this) {
      case ImageRotation.rotation0:
        return [
          [1, 0],
          [0, 1],
        ];
      case ImageRotation.rotation90:
        return [
          [0, -1],
          [1, 0],
        ];
      case ImageRotation.rotation180:
        return [
          [-1, 0],
          [0, -1],
        ];
      case ImageRotation.rotation270:
        return [
          [0, 1],
          [-1, 0],
        ];
    }
  }
}
