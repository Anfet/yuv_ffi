import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart' show Alignment, Matrix4, MatrixUtils;
import 'package:yuv_ffi/src/yuv/shared/yuv_image_rotation.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Describes how source, upright, and view coordinates relate for one frame.
///
/// Source coordinates are pixels as the frame arrived. Upright coordinates are
/// source pixels after [YuvFrameOrientation.rotation], before mirroring. View
/// coordinates are the logical pixels of the widget that displays the frame.
final class YuvFrameOrientation {
  /// Clockwise rotation that makes the source frame upright.
  final YuvImageRotation rotation;

  /// Whether to mirror horizontally after [rotation].
  final bool mirrored;

  /// Creates a source orientation.
  const YuvFrameOrientation({this.rotation = YuvImageRotation.rotation0, this.mirrored = false});

  /// An already upright, non-mirrored source.
  static const upright = YuvFrameOrientation();

  /// Returns a new image rotated and then mirrored according to this orientation.
  YuvImage applyTo(YuvImage source) {
    final result = source.rotated(rotation);
    return mirrored ? result.applyFlipHorizontal() : result;
  }

  @override
  bool operator ==(Object other) => other is YuvFrameOrientation && other.rotation == rotation && other.mirrored == mirrored;

  @override
  int get hashCode => Object.hash(rotation, mirrored);
}

/// Chooses whether a frame remains entirely visible or fills its view.
enum YuvFrameFit {
  /// Scales the entire frame into the view, leaving unused space if necessary.
  contain,

  /// Scales the frame to fill the view, clipping excess pixels if necessary.
  cover,
}

/// Maps a frame between source, upright, and view coordinate spaces.
///
/// Source coordinates are pixels as the frame arrived. Upright coordinates are
/// source pixels after rotation but before mirroring. View coordinates are the
/// logical pixels of the widget that displays the frame.
///
/// ML Kit receives the raw source with [YuvFrameOrientation.rotation] in its
/// metadata. Its upright bounding boxes map to the display with
/// `MatrixUtils.transformRect(uprightToView, box)`; mirroring is therefore
/// applied only after ML Kit has interpreted the raw frame.
final class YuvFrameGeometry {
  /// Source frame size in pixels.
  final Size sourceSize;

  /// Logical display size in pixels.
  final Size viewSize;

  /// Source rotation and post-rotation mirror.
  final YuvFrameOrientation orientation;

  /// Whether the whole frame fits or the view is covered.
  final YuvFrameFit fit;

  /// Placement within unused view space.
  final Alignment alignment;

  /// Where the upright frame is drawn in view coordinates.
  late final Rect destinationRect = Rect.fromLTWH(_translationX, _translationY, _uprightSize.width * _scale, _uprightSize.height * _scale);

  /// Maps source points to view coordinates.
  late final Matrix4 sourceToView = _sourceToViewMatrix();

  /// Maps view points back to source coordinates.
  late final Matrix4 viewToSource = Matrix4.inverted(sourceToView);

  /// Maps ML Kit's upright points to view coordinates.
  late final Matrix4 uprightToView = _affine(
    a: orientation.mirrored ? -_scale : _scale,
    d: _scale,
    tx: _translationX + (orientation.mirrored ? _scale * _uprightSize.width : 0),
    ty: _translationY,
  );

  /// Part of the source frame that is visible in the view.
  late final Rect visibleSourceRect = MatrixUtils.transformRect(viewToSource, destinationRect.intersect(Offset.zero & viewSize));

  late final Size _uprightSize = orientation.rotation.swapSize ? Size(sourceSize.height, sourceSize.width) : sourceSize;
  late final double _scale = switch (fit) {
    YuvFrameFit.contain => math.min(viewSize.width / _uprightSize.width, viewSize.height / _uprightSize.height),
    YuvFrameFit.cover => math.max(viewSize.width / _uprightSize.width, viewSize.height / _uprightSize.height),
  };
  late final double _translationX = (viewSize.width - _uprightSize.width * _scale) * (alignment.x + 1) / 2;
  late final double _translationY = (viewSize.height - _uprightSize.height * _scale) * (alignment.y + 1) / 2;

  /// Creates an immutable mapping for a positive source and view size.
  YuvFrameGeometry({
    required this.sourceSize,
    required this.viewSize,
    this.orientation = YuvFrameOrientation.upright,
    this.fit = YuvFrameFit.contain,
    this.alignment = Alignment.center,
  }) {
    if (sourceSize.width <= 0 || sourceSize.height <= 0 || viewSize.width <= 0 || viewSize.height <= 0) {
      throw ArgumentError('sourceSize and viewSize must be positive.');
    }
  }

  /// Returns an independent image containing the visible source area, with
  /// the configured rotation and mirror applied.
  ///
  /// This is a data operation rather than a screenshot: for 4:2:0 frames an
  /// odd crop size or origin recomputes chroma from 2×2 pixel blocks, so its
  /// colors can differ from pixels shown on screen.
  YuvImage apply(YuvImage source) {
    if (source.size != sourceSize) {
      throw ArgumentError.value(source.size, 'source', 'must match sourceSize.');
    }
    return orientation.applyTo(source.cropped(visibleSourceRect));
  }

  /// Copies this geometry with selected fields replaced.
  YuvFrameGeometry copyWith({Size? sourceSize, Size? viewSize, YuvFrameOrientation? orientation, YuvFrameFit? fit, Alignment? alignment}) =>
      YuvFrameGeometry(
        sourceSize: sourceSize ?? this.sourceSize,
        viewSize: viewSize ?? this.viewSize,
        orientation: orientation ?? this.orientation,
        fit: fit ?? this.fit,
        alignment: alignment ?? this.alignment,
      );

  @override
  bool operator ==(Object other) =>
      other is YuvFrameGeometry &&
      other.sourceSize == sourceSize &&
      other.viewSize == viewSize &&
      other.orientation == orientation &&
      other.fit == fit &&
      other.alignment == alignment;

  @override
  int get hashCode => Object.hash(sourceSize, viewSize, orientation, fit, alignment);

  Matrix4 _sourceToViewMatrix() {
    final transform = switch (orientation.rotation) {
      YuvImageRotation.rotation0 => (a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0),
      YuvImageRotation.rotation90 => (a: 0.0, b: -1.0, c: 1.0, d: 0.0, tx: sourceSize.height, ty: 0.0),
      YuvImageRotation.rotation180 => (a: -1.0, b: 0.0, c: 0.0, d: -1.0, tx: sourceSize.width, ty: sourceSize.height),
      YuvImageRotation.rotation270 => (a: 0.0, b: 1.0, c: -1.0, d: 0.0, tx: 0.0, ty: sourceSize.width),
    };
    final horizontalScale = orientation.mirrored ? -_scale : _scale;
    return _affine(
      a: horizontalScale * transform.a,
      b: horizontalScale * transform.b,
      c: _scale * transform.c,
      d: _scale * transform.d,
      tx: _translationX + horizontalScale * transform.tx + (orientation.mirrored ? _scale * _uprightSize.width : 0),
      ty: _translationY + _scale * transform.ty,
    );
  }
}

Matrix4 _affine({double a = 1, double b = 0, double c = 0, double d = 1, double tx = 0, double ty = 0}) => Matrix4.identity()
  ..setEntry(0, 0, a)
  ..setEntry(0, 1, b)
  ..setEntry(0, 3, tx)
  ..setEntry(1, 0, c)
  ..setEntry(1, 1, d)
  ..setEntry(1, 3, ty);
