@Tags(['contract'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  setUpAll(YuvFfi.initialize);

  for (final format in YuvPixelFormat.values) {
    group(format.name, () {
      test('inserts at origin, inside, and the odd bottom-right edge', () {
        for (final point in <(int, int, int, int)>[(0, 0, 2, 2), (2, 2, 2, 2), (4, 2, 3, 3)]) {
          final target = _image(format, 7, 5, seed: 11);
          final fragment = _image(format, point.$3, point.$4, seed: 101);
          _expectPatch(target, fragment, point.$1, point.$2);
        }
      });

      test('preserves padding and pixel gaps', () {
        final target = _image(format, 6, 4, seed: 7, gap: true);
        final fragment = _image(format, 2, 2, seed: 137, gap: true);
        _expectPatch(target, fragment, 2, 2);
      });

      test('accepts a rotated fragment', () {
        final target = _image(format, 6, 6, seed: 3);
        final fragment = _image(format, 2, 4, seed: 83).rotated(YuvImageRotation.rotation90);
        _expectPatch(target, fragment, 2, 2);
      });
    });
  }

  test('rejects invalid requests without changing bytes or revision', () {
    final requests = <void Function(YuvImage)>[
      (target) => target.applyPatch(YuvImage.nv12(2, 2), x: 0, y: 0),
      (target) => target.applyPatch(target, x: 0, y: 0),
      (target) => target.applyPatch(YuvImage.i420(2, 2), x: -1, y: 0),
      (target) => target.applyPatch(YuvImage.i420(2, 2), x: 0, y: -1),
      (target) => target.applyPatch(YuvImage.i420(2, 2), x: 7, y: 0),
      (target) => target.applyPatch(YuvImage.i420(2, 2), x: 0, y: 7),
      (target) => target.applyPatch(YuvImage.i420(2, 2), x: 1, y: 0),
      (target) => target.applyPatch(YuvImage.i420(2, 2), x: 0, y: 1),
      (target) => target.applyPatch(YuvImage.i420(3, 2), x: 0, y: 0),
      (target) => target.applyPatch(YuvImage.i420(2, 3), x: 0, y: 0),
    ];
    for (final request in requests) {
      final target = _image(YuvPixelFormat.i420, 8, 8, seed: 19, gap: true);
      final before = target.planes.map((plane) => Uint8List.fromList(plane.bytes)).toList();
      final revision = target.revision;
      expect(() => request(target), throwsArgumentError);
      expect(target.revision, revision);
      for (int i = 0; i < before.length; i++) {
        expect(target.planes[i].bytes, before[i]);
      }
    }
  });
}

void _expectPatch(YuvImage target, YuvImage fragment, int x, int y) {
  final before = target.planes.map((plane) => Uint8List.fromList(plane.bytes)).toList();
  final source = fragment.planes.map((plane) => Uint8List.fromList(plane.bytes)).toList();
  final revision = target.revision;

  expect(target.applyPatch(fragment, x: x, y: y), same(target));
  expect(target.revision, revision + 1);
  for (int i = 0; i < source.length; i++) {
    expect(fragment.planes[i].bytes, source[i]);
  }

  final specs = _specs(target.format, fragment.width, fragment.height, x, y);
  for (int i = 0; i < specs.length; i++) {
    final spec = specs[i];
    final targetPlane = target.planes[i];
    final sourcePlane = fragment.planes[i];
    final expected = Uint8List.fromList(before[i]);
    for (int row = 0; row < spec.$2; row++) {
      for (int column = 0; column < spec.$1; column++) {
        for (int byte = 0; byte < spec.$5; byte++) {
          expected[(spec.$4 + row) * targetPlane.rowStride + (spec.$3 + column) * targetPlane.pixelStride + byte] =
              sourcePlane.bytes[row * sourcePlane.rowStride + column * sourcePlane.pixelStride + byte];
        }
      }
    }
    expect(targetPlane.bytes, expected);
  }
}

YuvImage _image(YuvPixelFormat format, int width, int height, {required int seed, bool gap = false}) {
  final planes = _planeGeometry(format, width, height).map((geometry) {
    final pixelStride = geometry.$3 + (gap && !(format == YuvPixelFormat.nv12 && geometry.$3 == 2) ? 2 : 0);
    final rowStride = geometry.$1 * pixelStride + (gap ? 3 : 0);
    final bytes = Uint8List(geometry.$2 * rowStride);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = (seed + i * 17) & 0xff;
    }
    return YuvPlane(geometry.$2, rowStride, pixelStride, bytes);
  }).toList();
  return YuvImage(format, width, height, planes: planes, layout: YuvPlaneLayout.preserve);
}

List<(int, int, int)> _planeGeometry(YuvPixelFormat format, int width, int height) => switch (format) {
  YuvPixelFormat.i420 => [(width, height, 1), ((width + 1) ~/ 2, (height + 1) ~/ 2, 1), ((width + 1) ~/ 2, (height + 1) ~/ 2, 1)],
  YuvPixelFormat.nv12 => [(width, height, 1), ((width + 1) ~/ 2, (height + 1) ~/ 2, 2)],
  YuvPixelFormat.bgra8888 => [(width, height, 4)],
};

List<(int, int, int, int, int)> _specs(YuvPixelFormat format, int width, int height, int x, int y) => switch (format) {
  YuvPixelFormat.i420 => [
    (width, height, x, y, 1),
    ((width + 1) ~/ 2, (height + 1) ~/ 2, x ~/ 2, y ~/ 2, 1),
    ((width + 1) ~/ 2, (height + 1) ~/ 2, x ~/ 2, y ~/ 2, 1),
  ],
  YuvPixelFormat.nv12 => [(width, height, x, y, 1), ((width + 1) ~/ 2, (height + 1) ~/ 2, x ~/ 2, y ~/ 2, 2)],
  YuvPixelFormat.bgra8888 => [(width, height, x, y, 4)],
};
