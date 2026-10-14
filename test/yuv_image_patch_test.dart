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

  test('validates every external plane before writing and supports valid wrappers', () {
    final target = _image(YuvPixelFormat.i420, 4, 4, seed: 9);
    final before = target.planes.map((plane) => Uint8List.fromList(plane.bytes)).toList();
    final revision = target.revision;
    final malformedSource = _ForeignImage(_image(YuvPixelFormat.i420, 2, 2, seed: 91), (planes) => planes.take(2).toList());
    expect(() => target.applyPatch(malformedSource, x: 0, y: 0), throwsArgumentError);
    expect(target.planes.map((plane) => plane.bytes), before);
    expect(target.revision, revision);

    final source = _ForeignImage(_image(YuvPixelFormat.i420, 2, 2, seed: 91), (planes) => planes);
    expect(target.applyPatch(source, x: 0, y: 0), same(target));
    expect(target.revision, revision + 1);
  });

  test('rejects a malformed external destination before writing any plane', () {
    final backing = _image(YuvPixelFormat.i420, 4, 4, seed: 23);
    final target = _ForeignImage(backing, (planes) => planes.take(2).toList());
    final fragment = _image(YuvPixelFormat.i420, 2, 2, seed: 109);
    final before = backing.planes.map((plane) => Uint8List.fromList(plane.bytes)).toList();
    final geometry = (target.format, target.width, target.height);
    final planeGeometry = target.planes.map((plane) => (plane.height, plane.rowStride, plane.pixelStride)).toList();
    final revision = target.revision;

    expect(() => target.applyPatch(fragment, x: 0, y: 0), throwsArgumentError);

    expect((target.format, target.width, target.height), geometry);
    expect(target.revision, revision);
    expect(target.planes.map((plane) => (plane.height, plane.rowStride, plane.pixelStride)), planeGeometry);
    for (int i = 0; i < before.length; i++) {
      expect(backing.planes[i].bytes, before[i]);
    }
  });

  test('successfully patches an external destination and bumps its revision once', () {
    final backing = _image(YuvPixelFormat.i420, 4, 4, seed: 31);
    final target = _ForeignImage(backing, (planes) => planes);
    final fragment = _image(YuvPixelFormat.i420, 2, 2, seed: 127);

    _expectPatch(target, fragment, 0, 0);
  });

  test('rejects aliased external planes before changing either image', () {
    final shared = Uint8List.fromList(List<int>.generate(8, (index) => index + 1));
    final overlappingBacking = Uint8List.fromList(List<int>.generate(12, (index) => index + 11));
    final multiPlaneBacking = Uint8List.fromList(List<int>.generate(10, (index) => index + 21));
    final separateBacking = Uint8List.fromList(List<int>.generate(16, (index) => index + 31));
    final layouts = <({String name, YuvImage target, YuvImage source, bool rejected})>[
      (name: 'one Uint8List', target: _foreignBgra(shared), source: _foreignBgra(shared), rejected: true),
      (
        name: 'overlapping Uint8List views',
        target: _foreignBgra(Uint8List.view(overlappingBacking.buffer, 4, 8)),
        source: _foreignBgra(Uint8List.view(overlappingBacking.buffer, 0, 8)),
        rejected: true,
      ),
      (
        name: 'overlap through different planes',
        target: _foreignI420(multiPlaneBacking, yOffset: 0, uOffset: 4, vOffset: 5),
        source: _foreignI420(multiPlaneBacking, yOffset: 6, uOffset: 2, vOffset: 7),
        rejected: true,
      ),
      (
        name: 'non-overlapping slices',
        target: _foreignBgra(Uint8List.view(separateBacking.buffer, 8, 8)),
        source: _foreignBgra(Uint8List.view(separateBacking.buffer, 0, 8)),
        rejected: false,
      ),
    ];

    for (final layout in layouts) {
      final targetBefore = _planeBytes(layout.target);
      final sourceBefore = _planeBytes(layout.source);
      final targetRevision = layout.target.revision;
      final sourceRevision = layout.source.revision;

      if (layout.rejected) {
        expect(() => layout.target.applyPatch(layout.source, x: 0, y: 0), throwsArgumentError, reason: layout.name);
        expect(layout.target.revision, targetRevision, reason: layout.name);
      } else {
        expect(layout.target.applyPatch(layout.source, x: 0, y: 0), same(layout.target), reason: layout.name);
        expect(layout.target.revision, targetRevision + 1, reason: layout.name);
      }
      expect(_planeBytes(layout.target), layout.rejected ? targetBefore : sourceBefore, reason: layout.name);
      expect(_planeBytes(layout.source), sourceBefore, reason: layout.name);
      expect(layout.source.revision, sourceRevision, reason: layout.name);
    }
  });
}

class _ForeignImage implements YuvImage {
  _ForeignImage(this.backing, this.selectPlanes) : _planes = null;

  _ForeignImage.planes(this.backing, this._planes) : selectPlanes = null;

  final YuvImage backing;
  final List<YuvPlane> Function(List<YuvPlane>)? selectPlanes;
  final List<YuvPlane>? _planes;

  @override
  YuvPixelFormat get format => backing.format;
  @override
  int get width => backing.width;
  @override
  int get height => backing.height;
  @override
  List<YuvPlane> get planes => _planes ?? selectPlanes!(backing.planes);

  @override
  dynamic noSuchMethod(Invocation invocation) => Function.apply(backing.noSuchMethod, [invocation]);
}

YuvImage _foreignBgra(Uint8List bytes) => _ForeignImage.planes(YuvImage.bgra(2, 1), <YuvPlane>[_ForeignPlane(1, 8, 4, bytes)]);

YuvImage _foreignI420(Uint8List backing, {required int yOffset, required int uOffset, required int vOffset}) =>
    _ForeignImage.planes(YuvImage(YuvPixelFormat.i420, 2, 2), <YuvPlane>[
      _ForeignPlane(2, 2, 1, Uint8List.view(backing.buffer, yOffset, 4)),
      _ForeignPlane(1, 1, 1, Uint8List.view(backing.buffer, uOffset, 1)),
      _ForeignPlane(1, 1, 1, Uint8List.view(backing.buffer, vOffset, 1)),
    ]);

class _ForeignPlane extends YuvPlane {
  _ForeignPlane(super.height, super.rowStride, super.pixelStride, this._backing);

  final Uint8List _backing;

  @override
  Uint8List get bytes => _backing;
}

List<Uint8List> _planeBytes(YuvImage image) => image.planes.map((plane) => Uint8List.fromList(plane.bytes)).toList();

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
