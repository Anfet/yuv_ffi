import 'dart:typed_data';

import 'package:yuv_ffi/yuv_ffi.dart';

import 'bench_matrix_core.dart';

YuvImage makeImageForFlip(BenchInput input) {
  final width = input.width;
  final height = input.height;
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  return switch (input.format) {
    'I420' => YuvImage.i420(
      width,
      height,
      yPixelStride: 1,
      uvPixelStride: 1,
      planes: <YuvPlane>[
        YuvPlane(height, width, 1, input.planes[0]),
        YuvPlane(chromaHeight, chromaWidth, 1, input.planes[1]),
        YuvPlane(chromaHeight, chromaWidth, 1, input.planes[2]),
      ],
    ),
    'NV12' => YuvImage.nv21(
      width,
      height,
      yPixelStride: 1,
      uvPixelStride: 2,
      planes: <YuvPlane>[YuvPlane(height, width, 1, input.planes[0]), YuvPlane(chromaHeight, 2 * chromaWidth, 2, input.planes[1])],
    ),
    'BGRA' => _bgra(input, width, height),
    _ => throw ArgumentError.value(input.format, 'input.format'),
  };
}

YuvImage _bgra(BenchInput input, int width, int height) {
  // 0.2.4 reports backing capacity for a direct BGRA plane; copy into blank.
  final image = YuvImage.bgra(width, height);
  image.planes.first.bytes.setAll(0, input.planes.single);
  return image;
}

Uint8List packFlipActiveSamples(Object result) {
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
