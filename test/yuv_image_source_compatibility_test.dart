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

  test('an external implementation is never keyed by a revision it does not report', () {
    // A foreign class cannot prove its frame is unchanged, so it deliberately
    // gets the pre-0.2.5 always-miss key rather than revision equality. Calling
    // markDirty() on it still advances the tracked revision (above), but that
    // revision is not what keys the cache for this kind of image.
    final image = _LegacyExternalImage(2, 2);

    final first = YuvImageProvider(image);
    expect(YuvImageProvider(image), isNot(equals(first)), reason: 'an unreported mutation must never be assumed absent');

    image.markDirty();
    expect(YuvImageProvider(image), isNot(equals(first)));
  });

  test('a legacy mutation without markDirty() never reuses the cached frame', () {
    // The regression this guards: a class written against 0.2.4 mutates through
    // its own standard methods and cannot call markDirty(), because that API did
    // not exist when it was written. If revision-based equality applied to it,
    // the provider built after the mutation would equal the one built before and
    // the widget would serve the previous frame.
    final image = _LegacyMutatingImage(2, 2);

    final before = YuvImageProvider(image);
    image.negate(); // mutates bytes, reports nothing

    expect(
      YuvImageProvider(image),
      isNot(equals(before)),
      reason: 'an implementation that cannot report mutations must never produce a reusable key',
    );
  });

  test('an untracked image misses the cache even when it is genuinely untouched', () {
    // The cost side of the same trade: without a mutation report there is no
    // evidence the frame is unchanged, so every provider is a fresh key.
    final image = _LegacyMutatingImage(2, 2);

    expect(YuvImageProvider(image), isNot(equals(YuvImageProvider(image))));
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

/// A pre-0.2.5 external [YuvImage] whose standard mutators actually mutate.
///
/// [_LegacyExternalImage] throws from every mutator, which cannot expose a cache
/// that trusts an unreported mutation. This one changes its bytes in place the
/// way a real implementation would and — like any class written before the
/// revision seam existed — tells nobody.
class _LegacyMutatingImage extends _LegacyExternalImage {
  _LegacyMutatingImage(super.width, super.height);

  @override
  YuvImage negate() {
    final bytes = yPlane.bytes;
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = 0xFF - bytes[i];
    }
    // Deliberately no markDirty(): this class predates that API.
    return this;
  }
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
  YuvImage applyPlanes(Iterable<YuvPlane> planes) => throw UnimplementedError();

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

  @override
  YuvImage applyRgbaBytes(Uint8List bytes) => throw UnimplementedError();

  @override
  YuvImage applyGrayscale() => throw UnimplementedError();

  @override
  YuvImage applyBlackWhite() => throw UnimplementedError();

  @override
  YuvImage applyNegate() => throw UnimplementedError();

  @override
  YuvImage applyGaussianBlur({required int radius, required double sigma}) => throw UnimplementedError();

  @override
  YuvImage applyMeanBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  @override
  YuvImage applyBoxBlur({required int radius, ui.Rect? region}) => throw UnimplementedError();

  @override
  YuvImage applyCrop(ui.Rect region) => throw UnimplementedError();

  @override
  YuvImage applyFlipHorizontal() => throw UnimplementedError();

  @override
  YuvImage applyFlipVertical() => throw UnimplementedError();

  @override
  YuvImage applyRotation(YuvImageRotation rotation) => throw UnimplementedError();

  @override
  YuvImage applyFormat(YuvPixelFormat format) => throw UnimplementedError();

  @override
  YuvImage applyChromaSwap() => throw UnimplementedError();

  @override
  YuvImage cropped(ui.Rect region) => throw UnimplementedError();

  @override
  YuvImage rotated(YuvImageRotation rotation) => throw UnimplementedError();

  @override
  YuvImage toI420() => throw UnimplementedError();

  @override
  YuvImage toNv12() => throw UnimplementedError();

  @override
  YuvImage toBgra() => throw UnimplementedError();

  @override
  Uint8List toBytes() => throw UnimplementedError();

  @override
  Uint8List toBgraBytes() => throw UnimplementedError();
}
