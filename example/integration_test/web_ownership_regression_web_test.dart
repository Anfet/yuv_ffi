import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Browser coverage for plane ownership and independent conversion results.
///
/// This must run through the example integration harness: unlike
/// `flutter test --platform chrome`, it serves the WASM asset bundle.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(YuvFfi.initialize);

  testWidgets('applyPlanes copies a gapped NV12 plane on WASM', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This regression must execute in a browser.');

    final image = YuvImage.nv12(4, 4, uvPixelStride: 3);
    final replacement = <YuvPlane>[
      YuvPlane(4, 4),
      YuvPlane(2, 6, 3, Uint8List.fromList(<int>[1, 2, 0xEE, 3, 4, 0xEE, 5, 6, 0xEE, 7, 8, 0xEE])),
    ];
    final revisionBefore = image.revision;

    image.applyPlanes(replacement);
    replacement[1].bytes[0] = 0xFF;

    expect(image.revision, revisionBefore + 1);
    expect(image.uPlane.pixelStride, 3);
    expect(image.uPlane.bytes[0], 1, reason: 'applyPlanes must copy rather than adopt caller storage.');
  });

  testWidgets('conversions and results own independent WASM buffers', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This regression must execute in a browser.');

    final source = YuvImage.nv12(4, 4, uvPixelStride: 3);
    source.uPlane.bytes[0] = 0x11;
    final copy = source.copy();
    source.uPlane.bytes[0] = 0x22;

    expect(copy.uPlane.pixelStride, 3);
    expect(copy.uPlane.bytes[0], 0x11, reason: 'copy() must not alias gapped NV12 storage.');

    const width = 4;
    const height = 4;
    final rgba = _solidRgba(width, height, r: 10, g: 20, b: 30);
    final convertedSource = YuvImage.bgra(width, height)..applyRgbaBytes(rgba);
    final i420 = convertedSource.toI420();
    final nv12 = convertedSource.toNv12();
    final bgra = i420.toBgra();
    final i420Before = i420.toBytes();
    final nv12Before = nv12.toBytes();
    final bgraBefore = bgra.toBytes();

    expect(i420.yPlane.bytes.toSet(), hasLength(1));
    expect(nv12.yPlane.bytes.toSet(), hasLength(1));
    _expectSolidBgra(bgra.toBgraBytes(), width, height, r: 10, g: 20, b: 30, tolerance: 20);

    convertedSource.applyNegate();
    expect(i420.toBytes(), orderedEquals(i420Before));
    expect(nv12.toBytes(), orderedEquals(nv12Before));
    expect(bgra.toBytes(), orderedEquals(bgraBefore));

    final cropSource = YuvImage.bgra(6, 6)..applyRgbaBytes(_solidRgba(6, 6, r: 9, g: 8, b: 7));
    final crop = cropSource.cropped(const ui.Rect.fromLTWH(1, 1, 3, 3));
    final rotation = cropSource.rotated(YuvImageRotation.rotation90);
    final cropBefore = crop.toBytes();
    final rotationBefore = rotation.toBytes();
    cropSource.applyNegate();

    expect(crop.toBytes(), orderedEquals(cropBefore));
    expect(rotation.toBytes(), orderedEquals(rotationBefore));
  });

  testWidgets('patch bytes and odd YUV rejection match the explicit geometry contract on WASM', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This regression must execute in a browser.');

    final patchCases = <({int x, int y, List<int> expected})>[
      (
        x: 1,
        y: 1,
        expected: <int>[
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          13,
          14,
          15,
          16,
          17,
          18,
          19,
          100,
          101,
          102,
          103,
          104,
          105,
          106,
          107,
          28,
          29,
          30,
          31,
          32,
          33,
          34,
          35,
          36,
          37,
          38,
          39,
          40,
          41,
          42,
          43,
          44,
          45,
          46,
          47,
        ],
      ),
      (
        x: 2,
        y: 2,
        expected: <int>[
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          13,
          14,
          15,
          16,
          17,
          18,
          19,
          20,
          21,
          22,
          23,
          24,
          25,
          26,
          27,
          28,
          29,
          30,
          31,
          32,
          33,
          34,
          35,
          36,
          37,
          38,
          39,
          100,
          101,
          102,
          103,
          104,
          105,
          106,
          107,
        ],
      ),
    ];
    for (final patchCase in patchCases) {
      final target = YuvImage.bgra(4, 3);
      target.yPlane.bytes.setAll(0, List<int>.generate(48, (index) => index));
      final fragment = YuvImage.bgra(2, 1);
      fragment.yPlane.bytes.setAll(0, <int>[100, 101, 102, 103, 104, 105, 106, 107]);
      final fragmentBefore = Uint8List.fromList(fragment.toBytes());
      final revisionBefore = target.revision;

      target.applyPatch(fragment, x: patchCase.x, y: patchCase.y);

      expect(target.toBytes(), orderedEquals(patchCase.expected));
      expect(fragment.toBytes(), orderedEquals(fragmentBefore));
      expect(target.revision, revisionBefore + 1);
    }

    final yuvTarget = YuvImage.i420(5, 3);
    yuvTarget.yPlane.bytes.setAll(0, List<int>.generate(15, (index) => index));
    yuvTarget.uPlane.bytes.setAll(0, List<int>.generate(6, (index) => 20 + index));
    yuvTarget.vPlane.bytes.setAll(0, List<int>.generate(6, (index) => 40 + index));
    final yuvBefore = Uint8List.fromList(yuvTarget.toBytes());
    final yuvRevision = yuvTarget.revision;
    expect(() => yuvTarget.applyPatch(YuvImage.i420(2, 2), x: 1, y: 0), throwsArgumentError);
    expect(yuvTarget.toBytes(), orderedEquals(yuvBefore));
    expect(yuvTarget.revision, yuvRevision);

    final geometry = YuvFrameGeometry(
      sourceSize: const ui.Size(5, 3),
      viewSize: const ui.Size(3, 5),
      orientation: const YuvFrameOrientation(rotation: YuvImageRotation.rotation90, mirrored: true),
    );
    expect(geometry.visibleSourceRect, const ui.Rect.fromLTWH(0, 0, 5, 3));

    final i420 = YuvImage.i420(5, 3);
    i420.yPlane.bytes.setAll(0, List<int>.generate(15, (index) => index));
    i420.uPlane.bytes.setAll(0, List<int>.generate(6, (index) => 20 + index));
    i420.vPlane.bytes.setAll(0, List<int>.generate(6, (index) => 40 + index));
    expect(
      geometry.apply(i420).toBytes(),
      orderedEquals(<int>[0, 5, 10, 1, 6, 11, 2, 7, 12, 3, 8, 13, 4, 9, 14, 121, 118, 120, 117, 119, 116, 119, 115, 118, 114, 117, 113]),
    );

    final bgra = YuvImage.bgra(5, 3);
    for (var index = 0; index < 15; index++) {
      bgra.yPlane.bytes.setRange(index * 4, index * 4 + 4, <int>[index, index + 40, index + 80, 255]);
    }
    expect(
      geometry.apply(bgra).toBgraBytes(),
      orderedEquals(<int>[
        0,
        40,
        80,
        255,
        5,
        45,
        85,
        255,
        10,
        50,
        90,
        255,
        1,
        41,
        81,
        255,
        6,
        46,
        86,
        255,
        11,
        51,
        91,
        255,
        2,
        42,
        82,
        255,
        7,
        47,
        87,
        255,
        12,
        52,
        92,
        255,
        3,
        43,
        83,
        255,
        8,
        48,
        88,
        255,
        13,
        53,
        93,
        255,
        4,
        44,
        84,
        255,
        9,
        49,
        89,
        255,
        14,
        54,
        94,
        255,
      ]),
    );
  });

  testWidgets('byte copies, padding and semantic no-ops hold on WASM', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This regression must execute in a browser.');

    const width = 3;
    const height = 5;
    const rowStride = width * 4 + 8;
    final backing = Uint8List(height * rowStride)..fillRange(0, height * rowStride, 0xA5);
    for (var row = 0; row < height; row++) {
      for (var column = 0; column < width; column++) {
        final offset = row * rowStride + column * 4;
        backing.setRange(offset, offset + 4, <int>[40, 80, 160, 255]);
      }
    }
    final padded = YuvImage.bgra(width, height, planes: <YuvPlane>[YuvPlane(height, rowStride, 4, backing)], layout: YuvPlaneLayout.preserve);

    final packed = padded.toBgraBytes();
    expect(packed.length, width * height * 4);
    expect(packed.toSet().contains(0xA5), isFalse, reason: 'toBgraBytes() must exclude row padding.');

    final packedBefore = Uint8List.fromList(packed);
    packed[0] ^= 0xFF;
    expect(padded.toBgraBytes(), orderedEquals(packedBefore));

    final bytes = padded.toBytes();
    final bytesBefore = Uint8List.fromList(bytes);
    bytes[0] ^= 0xFF;
    expect(padded.toBytes(), orderedEquals(bytesBefore));

    final revisionBefore = (padded as YuvRevisionAware).internalRevision;
    final fullFrame = padded.cropped(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    expect(identical(fullFrame, padded), isFalse);
    expect((padded as YuvRevisionAware).internalRevision, revisionBefore);
    final fullFrameBefore = fullFrame.toBytes();
    padded.yPlane.bytes[0] ^= 0xFF;
    padded.markDirty();
    expect(fullFrame.toBytes(), orderedEquals(fullFrameBefore));

    final matchingNv12 = YuvImage.nv12(4, 4);
    final matchingNv12Revision = (matchingNv12 as YuvRevisionAware).internalRevision;
    final nv12Copy = matchingNv12.toNv12();
    expect(identical(nv12Copy, matchingNv12), isFalse);
    expect((matchingNv12 as YuvRevisionAware).internalRevision, matchingNv12Revision);

    final matchingBgra = YuvImage.bgra(4, 4);
    final matchingBgraRevision = (matchingBgra as YuvRevisionAware).internalRevision;
    final bgraCopy = matchingBgra.toBgra();
    expect(identical(bgraCopy, matchingBgra), isFalse);
    expect((matchingBgra as YuvRevisionAware).internalRevision, matchingBgraRevision);
  });
}

Uint8List _solidRgba(int width, int height, {required int r, required int g, required int b}) {
  final bytes = Uint8List(width * height * 4);
  for (var offset = 0; offset < bytes.length; offset += 4) {
    bytes[offset] = r;
    bytes[offset + 1] = g;
    bytes[offset + 2] = b;
    bytes[offset + 3] = 255;
  }
  return bytes;
}

void _expectSolidBgra(Uint8List bytes, int width, int height, {required int r, required int g, required int b, required int tolerance}) {
  expect(bytes.length, width * height * 4);
  for (var offset = 0; offset < bytes.length; offset += 4) {
    expect((bytes[offset] - b).abs(), lessThanOrEqualTo(tolerance));
    expect((bytes[offset + 1] - g).abs(), lessThanOrEqualTo(tolerance));
    expect((bytes[offset + 2] - r).abs(), lessThanOrEqualTo(tolerance));
    expect(bytes[offset + 3], 255);
  }
}
