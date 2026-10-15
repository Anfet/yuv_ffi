@Tags(['contract'])
library;

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  setUpAll(() async {
    await YuvFfi.initialize();
  });

  test('Gaussian blur preserves a constant BGRA pixel for finite positive sigma extremes', () {
    for (final sigma in <double>[1e-200, double.minPositive, 1.5, double.maxFinite]) {
      final plane = YuvPlane(1, 4, 4, Uint8List.fromList(<int>[120, 90, 60, 255]));
      final image = YuvImage.bgra(1, 1, planes: <YuvPlane>[plane]);

      image.applyGaussianBlur(radius: 1, sigma: sigma);

      expect(image.toBgraBytes(), orderedEquals(<int>[120, 90, 60, 255]), reason: 'sigma=$sigma');
    }
  });

  test('Gaussian blur preserves constant I420 and NV12 planes for finite positive sigma extremes', () {
    const width = 4;
    const height = 4;
    final cases = <({String name, YuvImage Function() create, List<List<int>> expected})>[
      (
        name: 'I420',
        create: () => YuvImage.i420(
          width,
          height,
          planes: <YuvPlane>[
            YuvPlane(height, width, 1, Uint8List.fromList(List<int>.filled(width * height, 96))),
            YuvPlane(height ~/ 2, width ~/ 2, 1, Uint8List.fromList(List<int>.filled(width * height ~/ 4, 90))),
            YuvPlane(height ~/ 2, width ~/ 2, 1, Uint8List.fromList(List<int>.filled(width * height ~/ 4, 170))),
          ],
        ),
        expected: <List<int>>[
          List<int>.filled(width * height, 96),
          List<int>.filled(width * height ~/ 4, 90),
          List<int>.filled(width * height ~/ 4, 170),
        ],
      ),
      (
        name: 'NV12',
        create: () => YuvImage.nv12(
          width,
          height,
          planes: <YuvPlane>[
            YuvPlane(height, width, 1, Uint8List.fromList(List<int>.filled(width * height, 96))),
            YuvPlane(
              height ~/ 2,
              width,
              2,
              Uint8List.fromList(<int>[
                for (var i = 0; i < width * height ~/ 4; i++) ...<int>[90, 170],
              ]),
            ),
          ],
        ),
        expected: <List<int>>[
          List<int>.filled(width * height, 96),
          <int>[
            for (var i = 0; i < width * height ~/ 4; i++) ...<int>[90, 170],
          ],
        ],
      ),
    ];

    for (final imageCase in cases) {
      for (final sigma in <double>[1e-200, double.minPositive, 1.5, double.maxFinite]) {
        final image = imageCase.create()..applyGaussianBlur(radius: 1, sigma: sigma);

        for (var planeIndex = 0; planeIndex < imageCase.expected.length; planeIndex++) {
          expect(
            image.planes[planeIndex].bytes,
            orderedEquals(imageCase.expected[planeIndex]),
            reason: '${imageCase.name} plane $planeIndex, sigma=$sigma',
          );
        }
      }
    }
  });
}
