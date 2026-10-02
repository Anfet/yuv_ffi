import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:yuv_ffi/src/geometry/yuv_frame_geometry.dart';
import 'package:yuv_ffi/src/widgets/yuv_frame_image_decoder.dart';
import 'package:yuv_ffi/src/widgets/yuv_planes_texture.dart';
import 'package:yuv_ffi/src/yuv/yuv.dart';

/// Uploads YUV frames for shader rendering and falls back to BGRA when needed.
final class YuvFrameRenderer {
  final ui.FragmentShader? _shader;

  YuvFrameRenderer._(this._shader);

  /// Loads the package shader; unavailable platforms retain the BGRA fallback.
  static Future<YuvFrameRenderer> load() async {
    try {
      return YuvFrameRenderer._((await ui.FragmentProgram.fromAsset('packages/yuv_ffi/shaders/yuv_frame.frag')).fragmentShader());
    } catch (_) {
      // Shader availability is optional; the documented BGRA path is the fallback.
      return YuvFrameRenderer._(null);
    }
  }

  /// Whether YUV planes can be rendered by the loaded shader.
  bool get hasShader => _shader != null;

  /// Copies [frame] before awaiting so it may be reused immediately.
  Future<YuvFrameTexture> upload(YuvImage frame) {
    final packed = hasShader ? YuvPlanesTexture.pack(frame) : null;
    if (packed != null) {
      return decodeYuvFrameImage(
        packed.bytes,
        packed.width,
        packed.height,
        ui.PixelFormat.rgba8888,
      ).then((image) => YuvFrameTexture._(frame.width, frame.height, image, packed));
    }
    final bytes = frame.toBgraBytes();
    return decodeYuvFrameImage(
      bytes,
      frame.width,
      frame.height,
      ui.PixelFormat.bgra8888,
    ).then((image) => YuvFrameTexture._(frame.width, frame.height, image, null));
  }

  /// Paints [texture] using [geometry].
  ///
  /// Each covered view pixel samples the source pixel containing its center,
  /// transformed through [YuvFrameGeometry.viewToSource]. Pixels outside the
  /// visible destination remain transparent.
  void paint(Canvas canvas, YuvFrameTexture texture, YuvFrameGeometry geometry) {
    if (texture.width != geometry.sourceSize.width || texture.height != geometry.sourceSize.height) {
      throw ArgumentError('texture size must match geometry.sourceSize.');
    }
    final clip = geometry.destinationRect.intersect(Offset.zero & geometry.viewSize);
    canvas.save();
    canvas.clipRect(clip);
    final packed = texture._packed;
    if (_shader != null && packed != null) {
      final matrix = geometry.viewToSource.storage;
      final values = <double>[
        texture.width.toDouble(),
        texture.height.toDouble(),
        packed.width.toDouble(),
        packed.height.toDouble(),
        matrix[0],
        matrix[1],
        matrix[4],
        matrix[5],
        matrix[12],
        matrix[13],
        packed.u.row.toDouble(),
        packed.u.offset.toDouble(),
        packed.u.step.toDouble(),
        packed.v.row.toDouble(),
        packed.v.offset.toDouble(),
        packed.v.step.toDouble(),
      ];
      for (var i = 0; i < values.length; i++) {
        _shader.setFloat(i, values[i]);
      }
      _shader.setImageSampler(0, texture._image, filterQuality: FilterQuality.none);
      canvas.drawRect(clip, Paint()..shader = _shader);
    } else {
      canvas.transform(geometry.sourceToView.storage);
      canvas.drawImage(texture._image, Offset.zero, Paint()..filterQuality = FilterQuality.none);
    }
    canvas.restore();
  }

  /// Releases shader resources.
  void dispose() => _shader?.dispose();
}

/// An uploaded immutable frame texture owned by a renderer client.
final class YuvFrameTexture {
  final int width, height;
  final ui.Image _image;
  final YuvPlanesTexture? _packed;

  YuvFrameTexture._(this.width, this.height, this._image, this._packed);

  /// Releases the uploaded image.
  void dispose() => _image.dispose();
}
