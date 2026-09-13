import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies YUV-20 source compatibility: a class written against `0.2.4` that
/// implements [YuvImage] without knowing anything about the revision seam must
/// still compile and work on `0.2.5`.
///
/// This file is the compile-time fixture required by the card. If revision
/// tracking ever moves back onto the [YuvImage] interface as required members,
/// [_LegacyExternalImage] stops compiling and this test fails to build — which
/// is exactly the regression it exists to catch.
void main() {
  test('a pre-0.2.5 external implementation still satisfies YuvImage', () {
    final YuvImage image = _LegacyExternalImage(2, 2);

    expect(image.width, 2);
    expect(image.height, 2);
    expect(image.format, YuvFileFormat.bgra8888);
  });

  test('the extension API works on an implementation that knows nothing about it', () {
    final YuvImage image = _LegacyExternalImage(2, 2);

    // Tracked externally, because this class does not carry a revision itself.
    final before = image.revision;
    image.markDirty();

    expect(image.revision, before + 1);
  });

  test('an external implementation still keys the image cache correctly', () {
    final image = _LegacyExternalImage(2, 2);

    final first = YuvImageProvider(image);
    expect(YuvImageProvider(image), equals(first), reason: 'an untouched frame must reuse its key');

    image.markDirty();
    expect(YuvImageProvider(image), isNot(equals(first)), reason: 'a marked frame must produce a new key');
  });

  test('two external implementations never share a revision', () {
    final a = _LegacyExternalImage(2, 2);
    final b = _LegacyExternalImage(2, 2);

    a.markDirty();
    a.markDirty();
    b.markDirty();

    expect(a.revision, 2);
    expect(b.revision, 1);
  });
}

/// A minimal external [YuvImage] as it could have been written against `0.2.4`.
///
/// It implements only the members that existed then. Nothing here mentions
/// `revision` or `markDirty`.
class _LegacyExternalImage implements YuvImage {
  _LegacyExternalImage(this.width, this.height) : _plane = YuvPlane(height, width * 4, 4, Uint8List(height * width * 4));

  final YuvPlane _plane;

  @override
  final int width;

  @override
  final int height;

  @override
  YuvFileFormat get format => YuvFileFormat.bgra8888;

  @override
  List<YuvPlane> get planes => <YuvPlane>[_plane];

  @override
  YuvPlane get yPlane => _plane;

  @override
  YuvPlane get uPlane => throw UnimplementedError();

  @override
  YuvPlane get vPlane => throw UnimplementedError();

  @override
  YuvPlane get y => _plane;

  @override
  YuvPlane? get u => null;

  @override
  YuvPlane? get v => null;

  @override
  ui.Size get size => ui.Size(width.toDouble(), height.toDouble());

  @override
  Uint8List getBytes() => _plane.bytes;

  @override
  YuvImage copy({bool blank = false}) => _LegacyExternalImage(width, height);

  @override
  Future<void> save(Sink<List<int>> sink) => throw UnimplementedError();

  @override
  Future<void> load(Stream<List<int>> stream) => throw UnimplementedError();

  @override
  YuvImage blackwhite() => throw UnimplementedError();

  @override
  YuvImage gaussianBlur({int radius = 2, int sigma = 2}) => throw UnimplementedError();

  @override
  YuvImage boxBlur({int radius = 10, ui.Rect? rect}) => throw UnimplementedError();

  @override
  YuvImage meanBlur({int radius = 2, ui.Rect? rect}) => throw UnimplementedError();

  @override
  YuvImage swapNv() => throw UnimplementedError();

  @override
  YuvImage toYuvNv21() => throw UnimplementedError();

  @override
  YuvImage toYuvI420() => throw UnimplementedError();

  @override
  YuvImage toYuvBgra8888() => this;

  @override
  YuvImage crop(ui.Rect rect) => throw UnimplementedError();

  @override
  YuvImage flipHorizontally() => throw UnimplementedError();

  @override
  YuvImage flipVertically() => throw UnimplementedError();

  @override
  void fromRgba8888(Uint8List bytes) => throw UnimplementedError();

  @override
  YuvImage grayscale() => throw UnimplementedError();

  @override
  YuvImage negate() => throw UnimplementedError();

  @override
  YuvImage rotate(YuvImageRotation rotation) => throw UnimplementedError();

  @override
  Uint8List toBgra8888() => _plane.bytes;

  @override
  Future<ui.Image> toImage() => throw UnimplementedError();
}
