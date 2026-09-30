import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// VIEW-04 prototype: draws a tight I420 frame with `shaders/view04_i420.frag`,
/// converting, turning and mirroring it on the GPU.
///
/// The three planes travel as one RGBA8888 texture `width / 4` wide and
/// `height * 1.5` tall, exactly the bytes of `YuvImage.toBytes()` for a tight
/// I420 frame, so both dimensions must be multiples of 4.
class View04I420Shader {
  /// The eight ways to turn and mirror a frame, as source-from-destination
  /// mappings `(m00, m01, m10, m11, offsetX, offsetY)` for a `width` x
  /// `height` source: the source pixel of output pixel `d` is
  /// `(m00*d.x + m01*d.y + offsetX, m10*d.x + m11*d.y + offsetY)`.
  static Map<String, List<double>> orientations(int width, int height) {
    final w = width - 1.0;
    final h = height - 1.0;
    return {
      'identity': [1, 0, 0, 1, 0, 0],
      'mirror_x': [-1, 0, 0, 1, w, 0],
      'mirror_y': [1, 0, 0, -1, 0, h],
      'rotate_180': [-1, 0, 0, -1, w, h],
      'transpose': [0, 1, 1, 0, 0, 0],
      'anti_transpose': [0, -1, -1, 0, w, h],
      'rotate_90_cw': [0, 1, -1, 0, 0, h],
      'rotate_90_ccw': [0, -1, 1, 0, w, 0],
    };
  }

  final ui.FragmentShader _shader;

  View04I420Shader._(this._shader);

  static Future<View04I420Shader> load() async =>
      View04I420Shader._((await ui.FragmentProgram.fromAsset('shaders/view04_i420.frag')).fragmentShader());

  /// The size of the drawn frame: swapped when [mapping] turns by a quarter.
  static Size outputSize(List<double> mapping, int width, int height) =>
      mapping[0] == 0 ? Size(height.toDouble(), width.toDouble()) : Size(width.toDouble(), height.toDouble());

  /// Uploads tight I420 [planes] of a [width] x [height] frame.
  static Future<ui.Image> planesTexture(Uint8List planes, int width, int height) =>
      texture(planes, width ~/ 4, height * 3 ~/ 2, ui.PixelFormat.rgba8888);

  /// The texture path `YuvFramePresenter` takes, for raw [bytes].
  static Future<ui.Image> texture(Uint8List bytes, int width, int height, ui.PixelFormat pixelFormat) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: pixelFormat);
    final codec = await descriptor.instantiateCodec();
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  void dispose() => _shader.dispose();

  /// Fills [rect] with the frame held in [planes], oriented by [mapping].
  /// Local coordinates of [rect] are output pixels, so the caller scales the
  /// canvas to fit.
  void draw(Canvas canvas, Rect rect, ui.Image planes, List<double> mapping) {
    // Float uniforms in declaration order: uFrameSize, uMap, uOffset,
    // uTextureSize. The frame size follows from the W/4 x H*1.5 texture.
    final floats = [planes.width * 4.0, planes.height * 2.0 / 3.0, ...mapping, planes.width.toDouble(), planes.height.toDouble()];
    for (var i = 0; i < floats.length; i++) {
      _shader.setFloat(i, floats[i]);
    }
    _shader.setImageSampler(0, planes);
    canvas.drawRect(rect, Paint()..shader = _shader);
  }

  /// Draws [planes] offscreen with every orientation and compares each with
  /// [expectedBgra], the CPU path's output. Returns the name of the first
  /// orientation that matches to within one level per channel, or `null`,
  /// plus the per-orientation differences for the log.
  Future<(String?, Map<String, Object>)> match(ui.Image planes, int width, int height, Uint8List expectedBgra) async {
    final report = <String, Object>{};
    String? matched;
    for (final MapEntry(key: name, value: mapping) in orientations(width, height).entries) {
      final size = outputSize(mapping, width, height);
      if (size.width * size.height * 4 != expectedBgra.length) {
        continue;
      }
      final recorder = ui.PictureRecorder();
      draw(Canvas(recorder), Offset.zero & size, planes, mapping);
      final image = recorder.endRecording().toImageSync(size.width.toInt(), size.height.toInt());
      final drawn = await image.toByteData();
      image.dispose();
      if (drawn == null) {
        throw StateError('shader output unreadable');
      }
      var maxDiff = 0;
      for (var p = 0; p < expectedBgra.length; p += 4) {
        for (final (rgba, bgra) in [(0, 2), (1, 1), (2, 0)]) {
          final diff = (drawn.getUint8(p + rgba) - expectedBgra[p + bgra]).abs();
          if (diff > maxDiff) maxDiff = diff;
        }
      }
      report[name] = maxDiff;
      if (matched == null && maxDiff <= 1) {
        matched = name;
      }
    }
    return (matched, report);
  }
}
