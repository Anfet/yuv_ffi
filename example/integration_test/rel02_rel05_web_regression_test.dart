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

  testWidgets('REL-05 result and no-op contracts hold on WASM', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This regression must execute in a browser.');

    final source = YuvImage.nv12(4, 4, uvPixelStride: 3);
    source.uPlane.bytes[0] = 0x11;
    final copy = source.copy();
    source.uPlane.bytes[0] = 0x22;

    expect(copy.uPlane.pixelStride, 3);
    expect(copy.uPlane.bytes[0], 0x11, reason: 'copy() must not alias gapped NV12 storage.');

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

    final revisionBefore = (padded as YuvRevisionAware).internalRevision;
    final fullFrame = padded.cropped(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    expect(identical(fullFrame, padded), isFalse);
    expect((padded as YuvRevisionAware).internalRevision, revisionBefore);
  });
}
