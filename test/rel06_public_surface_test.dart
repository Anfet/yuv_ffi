// Deliberately imports no internal `package:yuv_ffi/src/...` path -- only
// Dart SDK libraries, the test framework, and `package:yuv_ffi/yuv_ffi.dart`
// itself -- unlike `rel06_deprecated_api_test.dart`'s hidden-impl check, which
// imports `YuvImageImpl` directly to prove it still exists and works. This
// file proves the other half of REL-06's "YuvImageImpl confirmed hidden"
// acceptance criterion: that a real consumer, reaching this package only
// through its public library, never needs -- and cannot reach -- the concrete
// backend class. Every `YuvImage` here is produced by a public factory and
// used only through `YuvImage`/its extensions; `YuvImageImpl` is never named.
// If a future change ever made some part of the public 0.3.0 surface require
// the concrete type (for example, a cast this file would then need), this
// file would fail to compile without adding an internal import -- which is
// the point: it is a compile-time proof that this package's own public
// consumer surface, including the full deprecated compatibility API, needs
// nothing beyond `package:yuv_ffi/yuv_ffi.dart`.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies REL-06's "YuvImageImpl confirmed hidden" acceptance criterion from
/// the actual consumer side: the complete `0.3.0` deprecated API surface is
/// reachable and usable through `package:yuv_ffi/yuv_ffi.dart` alone.
void main() {
  test('every named/unnamed factory is reachable through the public library alone', () {
    final YuvImage i420 = YuvImage.i420(4, 4);
    final YuvImage nv12 = YuvImage.nv12(4, 4);
    final YuvImage bgra = YuvImage.bgra(4, 4);
    final YuvImage allocated = YuvImage.allocate(YuvPixelFormat.i420, 4, 4);
    // ignore: deprecated_member_use
    final YuvImage nv21 = YuvImage.nv21(4, 4);
    // ignore: deprecated_member_use
    final YuvImage explicit = YuvImage(YuvFileFormat.i420, 4, 4);

    for (final image in <YuvImage>[i420, nv12, bgra, allocated, nv21, explicit]) {
      expect(image.width, 4);
      expect(image.height, 4);
    }

    // YuvImage.fromRgbaBytes() type-checks the same way. Its factory body
    // always converts through the real backend (no capability gate on this
    // path), so it succeeds on a host with a real native/WASM library and
    // throws on one without -- either way it must not crash the test runner
    // with something other than a normal Dart exception. Byte-exact and
    // fake-library-seam dispatch coverage lives in
    // `rel06_deprecated_api_test.dart`; this only proves the public call
    // compiles and dispatches.
    try {
      YuvImage.fromRgbaBytes(_solidRgba(4, 4), width: 4, height: 4, format: YuvPixelFormat.bgra8888);
    } catch (_) {
      // Expected on a host without a real native/WASM library.
    }
  });

  test('the full deprecated 0.3.0 instance-method surface compiles and runs through the public library alone', () {
    final YuvImage image = YuvImage.bgra(4, 4);

    // Plane aliases.
    // ignore: deprecated_member_use
    expect(image.y, same(image.yPlane));
    // ignore: deprecated_member_use
    expect(image.u, isNull);
    // ignore: deprecated_member_use
    expect(image.v, isNull);

    // Byte accessors.
    // ignore: deprecated_member_use
    expect(image.getBytes(), image.toBytes());
    // ignore: deprecated_member_use
    expect(image.toBgra8888(), image.toBgraBytes());

    // copy(blank:) with the deprecated named argument.
    // ignore: deprecated_member_use
    final blank = image.copy(blank: true);
    expect(blank.width, image.width);

    // Every deprecated mutator is a legal call through this public-only
    // surface -- it type-checks and dispatches all the way into the real
    // deprecated extension method and its capability-ungated legacy adapter.
    // This file cannot reach `YuvFfi.initialize()`'s fake-library test seam
    // (that seam lives outside what a public-surface-only consumer has
    // access to), so whether the call succeeds depends on whether this host
    // has a real native/WASM library; either way it must not crash the test
    // runner with something other than a normal Dart exception.
    // `rel06_deprecated_api_test.dart` covers successful dispatch and byte
    // behavior against the fake library deterministically.
    try {
      // ignore: deprecated_member_use
      image.blackwhite();
    } catch (_) {
      // Expected on a host without a real native/WASM library.
    }
  });

  test('a foreign implements YuvImage still compiles the complete YuvImage surface through the public library alone', () {
    final YuvImage image = _PublicSurfaceOnlyImage(4, 4);
    expect(image.width, 4);
    expect(image.height, 4);
    // ignore: deprecated_member_use
    expect(image.y, same(image.yPlane));
  });
}

Uint8List _solidRgba(int w, int h) {
  final out = Uint8List(w * h * 4);
  for (int i = 0; i < out.length; i += 4) {
    out[i] = 10;
    out[i + 1] = 20;
    out[i + 2] = 30;
    out[i + 3] = 255;
  }
  return out;
}

/// A foreign `implements YuvImage` written using only the public surface,
/// proving that a real external consumer can satisfy the interface (and use
/// the deprecated extension on it) without ever seeing `YuvImageImpl`.
class _PublicSurfaceOnlyImage implements YuvImage {
  _PublicSurfaceOnlyImage(this.width, this.height) : _plane = YuvPlane(height, width * 4, 4, Uint8List(height * width * 4));

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
  ui.Size get size => ui.Size(width.toDouble(), height.toDouble());

  @override
  YuvImage copy({bool blank = false}) => _PublicSurfaceOnlyImage(width, height);

  @override
  YuvImage applyPlanes(Iterable<YuvPlane> planes) => throw UnimplementedError();

  @override
  Future<void> save(Sink<List<int>> sink) => throw UnimplementedError();

  @override
  Future<void> load(Stream<List<int>> stream) => throw UnimplementedError();

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
  Uint8List toBytes() => _plane.bytes;

  @override
  Uint8List toBgraBytes() => _plane.bytes;
}
