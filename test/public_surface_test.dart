@Tags(['contract'])
library;

// Import only the published package library, as an external consumer does.
// The checks below build the current public formats and implement YuvImage
// outside the package.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies that current public factories, extensions, and the YuvImage
/// interface are usable through `package:yuv_ffi/yuv_ffi.dart` alone.
void main() {
  test('every named/unnamed factory is reachable through the public library alone', () {
    final YuvImage i420 = YuvImage.i420(4, 4);
    final YuvImage nv12 = YuvImage.nv12(4, 4);
    final YuvImage bgra = YuvImage.bgra(4, 4);
    final YuvImage allocated = YuvImage.allocate(YuvPixelFormat.i420, 4, 4);
    final YuvImage explicit = YuvImage(YuvPixelFormat.i420, 4, 4);

    for (final image in <YuvImage>[i420, nv12, bgra, allocated, explicit]) {
      expect(image.width, 4);
      expect(image.height, 4);
    }

    final geometry = YuvFrameGeometry(sourceSize: const ui.Size(4, 4), viewSize: const ui.Size(8, 8));
    expect(geometry.destinationRect, const ui.Rect.fromLTWH(0, 0, 8, 8));

    // The factory compiles through the public API and may throw a normal Dart
    // exception on hosts without an initialized native/WASM backend.
    try {
      YuvImage.fromRgbaBytes(_solidRgba(4, 4), width: 4, height: 4, format: YuvPixelFormat.bgra8888);
    } catch (_) {
      // Expected on a host without a real native/WASM library.
    }
  });

  test('a foreign implements YuvImage still compiles the complete YuvImage surface through the public library alone', () {
    final YuvImage image = _PublicSurfaceOnlyImage(4, 4);
    expect(image.width, 4);
    expect(image.height, 4);
    expect(image.yPlane, same(image.planes.single));
  });

  test('frame renderer is reachable through the public library alone', () async {
    final renderer = await YuvFrameRenderer.load();
    final texture = await renderer.upload(YuvImage.bgra(1, 1));

    expect(texture.width, 1);
    expect(texture.height, 1);

    texture.dispose();
    renderer.dispose();
  });

  test('patch extension is reachable and tracks a foreign implementation', () {
    final target = _PublicSurfaceOnlyImage(4, 4);
    final fragment = _PublicSurfaceOnlyImage(2, 2);

    expect(target.applyPatch(fragment, x: 1, y: 1), same(target));
    expect(target.revision, 1);
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

/// A foreign `implements YuvImage` using only the published interface.
class _PublicSurfaceOnlyImage implements YuvImage {
  _PublicSurfaceOnlyImage(this.width, this.height) : _plane = YuvPlane(height, width * 4, 4, Uint8List(height * width * 4));

  final YuvPlane _plane;

  @override
  final int width;

  @override
  final int height;

  @override
  YuvPixelFormat get format => YuvPixelFormat.bgra8888;

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
  YuvImage copy() => _PublicSurfaceOnlyImage(width, height);

  @override
  YuvImage applyPlanes(Iterable<YuvPlane> planes) => throw UnimplementedError();

  @override
  Future<void> encodeTo(Sink<List<int>> sink) => throw UnimplementedError();

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
