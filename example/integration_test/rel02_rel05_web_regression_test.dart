import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_revision.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Browser regression coverage for REL-02 and REL-05.
///
/// This must run through the example integration harness: unlike
/// `flutter test --platform chrome`, it serves the WASM asset bundle.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(YuvFfi.initialize);

  testWidgets('REL-02 applyPlanes copies a gapped NV12 plane on WASM', (tester) async {
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

  testWidgets('REL-05 conversions and results own independent WASM buffers', (tester) async {
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

  testWidgets('REL-05 byte copies, padding and semantic no-ops hold on WASM', (tester) async {
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
    final padded = YuvImage.bgra(width, height, planes: <YuvPlane>[YuvPlane(height, rowStride, 4, backing)]);

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
