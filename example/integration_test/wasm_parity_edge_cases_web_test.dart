import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// `toBgraBytes()` on a padded BGRA source must
/// return exactly `width * height * 4` tightly packed bytes, never the padded
/// plane verbatim.
///
/// A padded source plane has a `rowStride` greater than `width * 4`; returning
/// its bytes directly would leak padding into the result. This test checks the
/// public contract against the real WASM backend and the native implementation.
///
/// This runs through the integration harness (see
/// `wasm_bootstrap_test.dart`) instead of `flutter test --platform chrome`,
/// which serves no asset bundle and cannot load the WASM module.
void main() {
  if (!kIsWeb) {
    return;
  }

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await YuvFfi.initialize();
  });

  testWidgets('Gaussian blur preserves constant BGRA for finite positive sigma extremes', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This regression must execute through the loaded WASM backend.');
    for (final sigma in <double>[1e-200, double.minPositive, 1.5, double.maxFinite]) {
      final plane = YuvPlane(1, 4, 4, Uint8List.fromList(<int>[120, 90, 60, 255]));
      final image = YuvImage.bgra(1, 1, planes: <YuvPlane>[plane]);

      image.applyGaussianBlur(radius: 1, sigma: sigma);

      expect(image.toBgraBytes(), orderedEquals(<int>[120, 90, 60, 255]), reason: 'sigma=$sigma');
    }
  });

  testWidgets('toBgraBytes repacks a padded BGRA plane into exactly width*height*4 tight bytes', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    expect(() => YuvImage.bgra(0x80000000, 1), throwsArgumentError);
    for (final pixelStride in [1, 2, 3]) {
      expect(
        () => YuvImage.bgra(1, 1, planes: [YuvPlane(1, 4, pixelStride, Uint8List(4))], layout: YuvPlaneLayout.preserve),
        throwsArgumentError,
        reason: 'pixelStride=$pixelStride',
      );
    }
    final validGap = YuvImage.bgra(1, 1, planes: [YuvPlane(1, 5, 5, Uint8List(5))], layout: YuvPlaneLayout.preserve);
    expect(validGap.yPlane.pixelStride, 5);

    final header = utf8.encode(jsonEncode(<String, Object>{'version': 2, 'formatId': 3, 'width': 0x80000000, 'height': 1}));
    final headerOnly = Uint8List(4 + header.length);
    ByteData.view(headerOnly.buffer).setUint32(0, header.length, Endian.little);
    headerOnly.setRange(4, headerOnly.length, header);
    await expectLater(YuvImage.decode(Stream<List<int>>.value(headerOnly)), throwsFormatException);

    const width = 5;
    const height = 3;
    const tightRowStride = width * 4;
    const paddedRowStride = tightRowStride + 16;

    final expectedTight = _buildTightBgraPattern(width, height);
    final paddedPlane = _plane(expectedTight, height: height, rowStride: paddedRowStride, usefulRowBytes: tightRowStride);
    final paddedSnapshot = Uint8List.fromList(paddedPlane.bytes);

    final image = YuvImage.bgra(width, height, planes: <YuvPlane>[paddedPlane], layout: YuvPlaneLayout.preserve);

    final result = image.toBgraBytes();

    expect(result.length, width * height * 4, reason: 'toBgraBytes must always return exactly width*height*4 bytes');
    expect(
      result,
      orderedEquals(expectedTight),
      reason: 'no padding byte (0xa5) may leak into the packed output, and pixel order must match the tight layout',
    );
    expect(result.any((byte) => byte == 0xa5), isFalse, reason: 'no 0xa5 padding byte may appear anywhere in the output');

    // The source plane on the constructed image must not be mutated by the call.
    expect(image.yPlane.bytes, orderedEquals(paddedSnapshot));
  });

  testWidgets('toBgraBytes on a tight BGRA plane (rowStride == width*4) returns the tight bytes unchanged', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    const width = 4;
    const height = 6;
    const tightRowStride = width * 4;

    final expectedTight = _buildTightBgraPattern(width, height);
    final tightPlane = _plane(expectedTight, height: height, rowStride: tightRowStride, usefulRowBytes: tightRowStride);
    final tightSnapshot = Uint8List.fromList(tightPlane.bytes);

    final image = YuvImage.bgra(width, height, planes: <YuvPlane>[tightPlane]);

    final result = image.toBgraBytes();

    expect(result.length, width * height * 4);
    expect(result, orderedEquals(expectedTight));

    // The source plane must not be mutated, and this must not be a live view
    // onto the backing buffer: mutating the result must not affect the plane.
    expect(image.yPlane.bytes, orderedEquals(tightSnapshot));
    result[0] = result[0] ^ 0xFF;
    expect(image.yPlane.bytes, orderedEquals(tightSnapshot));
  });
}

/// Builds a deterministic, fully opaque tight BGRA pattern of
/// `width * height * 4` bytes so distinct pixels cannot coincidentally match.
Uint8List _buildTightBgraPattern(int width, int height) {
  final out = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      out[i] = (x * 11 + y * 5) & 0xFF; // B
      out[i + 1] = (x * 7 + y * 13) & 0xFF; // G
      out[i + 2] = (x * 3 + y * 17) & 0xFF; // R
      out[i + 3] = 255; // A
    }
  }
  return out;
}

/// Builds a [YuvPlane] whose rows carry [tight]'s bytes followed by
/// distinguishable `0xa5` padding, matching the convention used by
/// the shared reference-matrix plane helper.
YuvPlane _plane(Uint8List tight, {required int height, required int rowStride, required int usefulRowBytes}) {
  final bytes = Uint8List(height * rowStride)..fillRange(0, height * rowStride, 0xa5);
  for (int row = 0; row < height; row++) {
    final destination = row * rowStride;
    final source = row * usefulRowBytes;
    bytes.setRange(destination, destination + usefulRowBytes, tight, source);
  }
  return YuvPlane(height, rowStride, 4, bytes);
}
