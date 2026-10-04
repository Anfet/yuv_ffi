import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:yuv_ffi/yuv_ffi.dart';

import 'probe/probe_seed.dart';
import 'yuv_frame_render_reference.dart';

/// Runs the shared native and Web shader comparison matrix without assertions.
Future<Map<String, int>> runShaderProbeCases(YuvFrameRenderer renderer) async {
  final maximumByCase = <String, int>{};

  for (final layout in _ShaderLayout.values) {
    for (final size in [(3, 5), (33, 17), (720, 480), (1920, 1080)]) {
      final orientations = size.$1 < 100
          ? [
              for (final rotation in YuvImageRotation.values)
                for (final mirrored in [false, true]) YuvFrameOrientation(rotation: rotation, mirrored: mirrored),
            ]
          : const [YuvFrameOrientation.upright, YuvFrameOrientation(rotation: YuvImageRotation.rotation270, mirrored: true)];
      final frame = _frame(layout, size.$1, size.$2);
      for (final orientation in orientations) {
        final maxDiff = await _renderDifference(
          renderer,
          frame,
          YuvFrameGeometry(sourceSize: frame.size, viewSize: _viewSize(size, orientation), orientation: orientation),
        );
        final key = '${size.$1}x${size.$2}';
        maximumByCase.update(key, (value) => math.max(value, maxDiff), ifAbsent: () => maxDiff);
      }
    }
  }

  final padded = _frame(_ShaderLayout.i420, 33, 17, padding: 7);
  maximumByCase['padding'] = await _renderDifference(renderer, padded, YuvFrameGeometry(sourceSize: padded.size, viewSize: padded.size));

  final scaled = _frame(_ShaderLayout.nv12, 33, 17);
  maximumByCase['scale_x2'] = await _renderDifference(renderer, scaled, YuvFrameGeometry(sourceSize: scaled.size, viewSize: const Size(66, 34)));

  final contained = _frame(_ShaderLayout.i420PixelStride2, 33, 17);
  maximumByCase['contain'] = await _renderDifference(renderer, contained, YuvFrameGeometry(sourceSize: contained.size, viewSize: const Size(66, 50)));

  return maximumByCase;
}

Size _viewSize((int, int) size, YuvFrameOrientation orientation) =>
    orientation.rotation.swapSize ? Size(size.$2.toDouble(), size.$1.toDouble()) : Size(size.$1.toDouble(), size.$2.toDouble());

enum _ShaderLayout { i420, i420PixelStride2, nv12 }

Future<int> _renderDifference(YuvFrameRenderer renderer, YuvImage frame, YuvFrameGeometry geometry) async {
  final texture = await renderer.upload(frame);
  final recorder = PictureRecorder();
  renderer.paint(Canvas(recorder), texture, geometry);
  final drawn = await recorder.endRecording().toImage(geometry.viewSize.width.toInt(), geometry.viewSize.height.toInt());
  final bytes = (await drawn.toByteData(format: ImageByteFormat.rawRgba))!.buffer.asUint8List();
  final expected = renderYuvFrameReference(frame, geometry);
  var maxDiff = 0;
  for (var i = 0; i < bytes.length; i++) {
    maxDiff = math.max(maxDiff, (bytes[i] - expected[i]).abs());
  }
  drawn.dispose();
  texture.dispose();
  return maxDiff;
}

YuvImage _frame(_ShaderLayout layout, int width, int height, {int padding = 0}) {
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  final yPlane = _plane(height, width + padding, 1, width * 31 + height);
  return switch (layout) {
    _ShaderLayout.i420 => YuvImage.i420(
      width,
      height,
      planes: [yPlane, _plane(chromaHeight, chromaWidth + padding, 1, 17), _plane(chromaHeight, chromaWidth + padding, 1, 29)],
      layout: YuvPlaneLayout.preserve,
    ),
    _ShaderLayout.i420PixelStride2 => YuvImage.i420(
      width,
      height,
      planes: [yPlane, _plane(chromaHeight, 2 * chromaWidth - 1 + padding, 2, 43), _plane(chromaHeight, 2 * chromaWidth - 1 + padding, 2, 59)],
      uvPixelStride: 2,
      layout: YuvPlaneLayout.preserve,
    ),
    _ShaderLayout.nv12 => YuvImage.nv12(
      width,
      height,
      planes: [yPlane, _plane(chromaHeight, 2 * chromaWidth + padding, 2, 71)],
      layout: YuvPlaneLayout.preserve,
    ),
  };
}

YuvPlane _plane(int height, int rowStride, int pixelStride, int seed) {
  var current = seed;
  return YuvPlane(
    height,
    rowStride,
    pixelStride,
    Uint8List.fromList(
      List.generate(height * rowStride, (_) {
        current = probeNextSeed(current);
        return current & 255;
      }),
    ),
  );
}
