import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:yuv_ffi/yuv_ffi.dart';

import 'bench_common.dart';

YuvImage makeImage(Scenario scenario, InputFrame input) {
  final format = input.format == 'RGBA' ? scenario.destinationFormat : input.format;
  final w = input.width;
  final h = input.height;
  final cw = (w + 1) ~/ 2;
  final ch = (h + 1) ~/ 2;
  return switch (format) {
    'I420' => YuvImage.i420(
      w,
      h,
      yPixelStride: 1,
      uvPixelStride: 1,
      planes: input.format == 'RGBA'
          ? null
          : <YuvPlane>[YuvPlane(h, w, 1, input.planes[0]), YuvPlane(ch, cw, 1, input.planes[1]), YuvPlane(ch, cw, 1, input.planes[2])],
    ),
    'NV12' => YuvImage.nv21(
      w,
      h,
      yPixelStride: 1,
      uvPixelStride: 2,
      planes: input.format == 'RGBA' ? null : <YuvPlane>[YuvPlane(h, w, 1, input.planes[0]), YuvPlane(ch, 2 * cw, 2, input.planes[1])],
    ),
    'BGRA' => _bgra(input, w, h),
    _ => throw ArgumentError.value(format),
  };
}

YuvImage _bgra(InputFrame input, int width, int height) {
  // The 0.2.4 BGRA constructor with planes can expose WriteBuffer capacity
  // instead of its used length; filling a blank image avoids that setup error.
  final image = YuvImage.bgra(width, height);
  if (input.format != 'RGBA') {
    image.planes.first.bytes.setAll(0, input.planes.single);
  }
  return image;
}

Uint8List outputBytes(Object result) {
  if (result is Uint8List) return result;
  final image = result as YuvImage;
  final planes = image.planes;
  final chromaWidth = (image.width + 1) ~/ 2;
  final chromaHeight = (image.height + 1) ~/ 2;
  final packed = BytesBuilder(copy: false);
  for (var index = 0; index < planes.length; index++) {
    final plane = planes[index];
    final width = index == 0 ? image.width : chromaWidth;
    final height = index == 0 ? image.height : chromaHeight;
    final sampleBytes = planes.length == 1
        ? 4
        : planes.length == 2 && index == 1
        ? 2
        : 1;
    for (var row = 0; row < height; row++) {
      final rowStart = row * plane.rowStride;
      if (plane.pixelStride == sampleBytes) {
        packed.add(Uint8List.sublistView(plane.bytes, rowStart, rowStart + width * sampleBytes));
      } else {
        for (var column = 0; column < width; column++) {
          final offset = rowStart + column * plane.pixelStride;
          packed.add(Uint8List.sublistView(plane.bytes, offset, offset + sampleBytes));
        }
      }
    }
  }
  return packed.takeBytes();
}

Rect region(int width, int height) =>
    Rect.fromLTRB((width ~/ 4).toDouble(), (height ~/ 4).toDouble(), (3 * width ~/ 4).toDouble(), (3 * height ~/ 4).toDouble());

Rect crop(Scenario scenario, int width, int height) {
  final odd = scenario.parts[2] == 'ODD' ? 1 : 0;
  return Rect.fromLTWH((width ~/ 4 + odd).toDouble(), (height ~/ 4 + odd).toDouble(), (width ~/ 2 - odd).toDouble(), (height ~/ 2 - odd).toDouble());
}

YuvImageRotation rotation(Scenario scenario) => switch (scenario.degrees) {
  0 => YuvImageRotation.rotation0,
  90 => YuvImageRotation.rotation90,
  180 => YuvImageRotation.rotation180,
  270 => YuvImageRotation.rotation270,
  _ => throw ArgumentError.value(scenario.degrees),
};
