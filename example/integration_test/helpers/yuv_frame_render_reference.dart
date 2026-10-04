import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/widgets.dart' show MatrixUtils;
import 'package:yuv_ffi/yuv_ffi.dart';

/// Renders the normative nearest-neighbour frame-display contract in Dart.
Uint8List renderYuvFrameReference(YuvImage frame, YuvFrameGeometry geometry) {
  if (frame.size != geometry.sourceSize) {
    throw ArgumentError.value(frame.size, 'frame', 'must match geometry.sourceSize.');
  }
  final viewWidth = geometry.viewSize.width.toInt();
  final viewHeight = geometry.viewSize.height.toInt();
  final source = frame.toBgraBytes();
  final result = Uint8List(viewWidth * viewHeight * 4);
  final visible = geometry.destinationRect.intersect(Offset.zero & geometry.viewSize);

  for (var y = 0; y < viewHeight; y++) {
    for (var x = 0; x < viewWidth; x++) {
      final center = Offset(x + 0.5, y + 0.5);
      if (!visible.contains(center)) {
        continue;
      }
      final sourcePoint = MatrixUtils.transformPoint(geometry.viewToSource, center);
      final sourceX = sourcePoint.dx.floor().clamp(0, frame.width - 1);
      final sourceY = sourcePoint.dy.floor().clamp(0, frame.height - 1);
      final sourceOffset = (sourceY * frame.width + sourceX) * 4;
      final destinationOffset = (y * viewWidth + x) * 4;
      result[destinationOffset] = source[sourceOffset + 2];
      result[destinationOffset + 1] = source[sourceOffset + 1];
      result[destinationOffset + 2] = source[sourceOffset];
      result[destinationOffset + 3] = source[sourceOffset + 3];
    }
  }
  return result;
}
