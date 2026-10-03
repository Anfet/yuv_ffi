@Tags(['contract'])
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Verifies the public `encodeTo(sink)` and static `YuvImage.decode(stream)`
/// APIs. These cases only allocate planes in Dart and never dispatch to a
/// native/WASM backend, so they run without a real `yuv_ffi` library.
void main() {
  Stream<List<int>> asStream(List<int> bytes) => Stream<List<int>>.value(bytes);

  Future<Uint8List> collect(Future<void> Function(Sink<List<int>> sink) write) async {
    final chunks = <List<int>>[];
    await write(_CollectingSink(chunks));
    return Uint8List.fromList(chunks.expand((chunk) => chunk).toList());
  }

  group('encodeTo', () {
    test('encodes identical bytes through independent sinks', () async {
      final image = YuvImage.i420(4, 4);
      for (int i = 0; i < image.yPlane.bytes.length; i++) {
        image.yPlane.bytes[i] = (i * 7 + 3) & 0xFF;
      }

      final viaEncodeTo = await collect(image.encodeTo);
      final secondEncode = await collect(image.encodeTo);

      expect(secondEncode, orderedEquals(viaEncodeTo));
    });

    test('encodeTo() does not mutate the source image', () async {
      final image = YuvImage.nv12(4, 4);
      final before = Uint8List.fromList(image.toBytes());
      final revisionBefore = image.revision;

      await collect(image.encodeTo);

      expect(image.toBytes(), orderedEquals(before));
      expect(image.revision, revisionBefore);
    });
  });

  group('static YuvImage.decode', () {
    test('round-trips format, dimensions, strides and bytes', () async {
      final source = YuvImage.i420(8, 8);
      for (int i = 0; i < source.planes.length; i++) {
        final bytes = source.planes[i].bytes;
        for (int j = 0; j < bytes.length; j++) {
          bytes[j] = ((i + 1) * 19 + j) & 0xFF;
        }
      }
      final payload = await collect(source.encodeTo);

      final decoded = await YuvImage.decode(asStream(payload));

      expect(decoded.format, source.format);
      expect(decoded.width, source.width);
      expect(decoded.height, source.height);
      expect(decoded.planes.length, source.planes.length);
      for (int i = 0; i < source.planes.length; i++) {
        expect(decoded.planes[i].rowStride, source.planes[i].rowStride, reason: 'plane $i rowStride');
        expect(decoded.planes[i].pixelStride, source.planes[i].pixelStride, reason: 'plane $i pixelStride');
        expect(decoded.planes[i].bytes, orderedEquals(source.planes[i].bytes), reason: 'plane $i bytes');
      }
    });

    test('round-trips a gapped NV12 chroma layout', () async {
      final source = YuvImage.nv12(4, 4, uvPixelStride: 3);
      for (int i = 0; i < source.uPlane.bytes.length; i++) {
        source.uPlane.bytes[i] = i + 1;
      }
      final payload = await collect(source.encodeTo);

      final decoded = await YuvImage.decode(asStream(payload));

      expect(decoded.format, YuvPixelFormat.nv12);
      expect(decoded.uPlane.pixelStride, 3);
      expect(decoded.uPlane.bytes, orderedEquals(source.uPlane.bytes));
    });

    test('returns a new, independent image and never mutates the source', () async {
      final source = YuvImage.bgra(2, 2);
      source.yPlane.bytes[0] = 42;
      final payload = await collect(source.encodeTo);
      final sourceBytesBefore = Uint8List.fromList(source.toBytes());
      final sourceRevisionBefore = source.revision;

      final decoded = await YuvImage.decode(asStream(payload));
      decoded.yPlane.bytes[0] = 7;

      expect(source.toBytes(), orderedEquals(sourceBytesBefore), reason: 'decode() must not touch any existing instance');
      expect(source.revision, sourceRevisionBefore);
      expect(source.yPlane.bytes[0], 42, reason: 'the new image must own independent storage');
    });

    test('throws FormatException for a malformed payload, exactly as YuvCodec.decodeStream does', () async {
      await expectLater(YuvImage.decode(asStream(const <int>[1, 2, 3])), throwsFormatException);
    });
  });

  group('decode produces an independent frame', () {
    test('preserves format, geometry and bytes in the returned frame', () async {
      final source = YuvImage.i420(8, 8);
      for (int i = 0; i < source.yPlane.bytes.length; i++) {
        source.yPlane.bytes[i] = (i + 5) & 0xFF;
      }
      final payload = await collect(source.encodeTo);

      final target = await YuvImage.decode(asStream(payload));

      expect(target.width, 8);
      expect(target.height, 8);
      expect(target.yPlane.bytes, orderedEquals(source.yPlane.bytes));
    });

    test('does not advance an unrelated frame revision on success', () async {
      final source = YuvImage.i420(4, 4);
      final payload = await collect(source.encodeTo);
      final target = YuvImage.i420(2, 2);
      final before = target.revision;

      final decoded = await YuvImage.decode(asStream(payload));

      expect(decoded.width, source.width);
      expect(target.revision, before);
    });

    test('preserves a gapped NV12 chroma layout', () async {
      final source = YuvImage.nv12(4, 4, uvPixelStride: 3);
      final payload = await collect(source.encodeTo);
      final target = await YuvImage.decode(asStream(payload));

      expect(target.format, YuvPixelFormat.nv12);
      expect(target.uPlane.pixelStride, 3);
    });

    test('a rejected payload leaves format, geometry, bytes and revision untouched', () async {
      final target = YuvImage.i420(4, 4);
      for (int i = 0; i < target.yPlane.bytes.length; i++) {
        target.yPlane.bytes[i] = (i + 1) & 0xFF;
      }
      final before = (
        width: target.width,
        height: target.height,
        format: target.format,
        revision: target.revision,
        bytes: Uint8List.fromList(target.toBytes()),
      );

      final source = YuvImage.i420(8, 8);
      final payload = await collect(source.encodeTo);

      await expectLater(YuvImage.decode(asStream(payload.sublist(0, payload.length ~/ 2))), throwsFormatException);

      expect(target.width, before.width);
      expect(target.height, before.height);
      expect(target.format, before.format);
      expect(target.revision, before.revision);
      expect(target.toBytes(), orderedEquals(before.bytes));
    });
  });

  group('decode ownership', () {
    test('does not mutate a foreign image', () async {
      final image = _ForeignImage(4, 4);
      final bytesBefore = Uint8List.fromList(image.yPlane.bytes);
      final source = YuvImage.bgra(4, 4);
      final payload = await collect(source.encodeTo);

      await YuvImage.decode(asStream(payload));

      expect(image.width, 4, reason: 'decode must not mutate another frame');
      expect(image.height, 4);
      expect(image.yPlane.bytes, orderedEquals(bytesBefore));
    });
  });
}

class _CollectingSink implements Sink<List<int>> {
  _CollectingSink(this.chunks);

  final List<List<int>> chunks;

  @override
  void add(List<int> data) => chunks.add(List<int>.from(data));

  @override
  void close() {}
}

/// A minimal foreign `YuvImage` implementation.
class _ForeignImage implements YuvImage {
  _ForeignImage(this.width, this.height) : _plane = YuvPlane(height, width * 4, 4, Uint8List(height * width * 4));

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
  YuvImage copy() => _ForeignImage(width, height);

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
