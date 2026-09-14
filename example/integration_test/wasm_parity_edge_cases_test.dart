import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Web acceptance for YUV-08: `toBgra8888()` on a padded BGRA source must
/// return exactly `width * height * 4` tightly packed bytes, never the padded
/// plane verbatim.
///
/// `lib/src/yuv/impl/web/yuv_web.dart`'s `toBgra8888()` used to return
/// `yPlane.bytes` unconditionally for the BGRA format, which is only correct
/// when the plane's `rowStride` already equals `width * 4`. When the source
/// plane carries row padding (`rowStride > width * 4`), that violated the
/// public contract by leaking padding bytes into the result. This test
/// exercises the fix against the real WASM backend, mirroring the native
/// reference behavior in `lib/src/yuv/impl/io/yuv_image.dart`.
///
/// This runs through this package's integration harness (see
/// `wasm_bootstrap_test.dart`) instead of `flutter test --platform chrome`,
/// which serves no asset bundle and cannot load the WASM module.
void main() {
  if (!kIsWeb) {
    return;
  }

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await YuvFfi.ensureInitialized();
  });

  testWidgets('toBgra8888 repacks a padded BGRA plane into exactly width*height*4 tight bytes', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    const width = 5;
    const height = 3;
    const tightRowStride = width * 4;
    const paddedRowStride = tightRowStride + 16;

    final expectedTight = _buildTightBgraPattern(width, height);
    final paddedPlane = _plane(expectedTight, height: height, rowStride: paddedRowStride, usefulRowBytes: tightRowStride);
    final paddedSnapshot = Uint8List.fromList(paddedPlane.bytes);

    final image = YuvImage.bgra(width, height, planes: <YuvPlane>[paddedPlane]);

    final result = image.toBgra8888();

    expect(result.length, width * height * 4, reason: 'toBgra8888 must always return exactly width*height*4 bytes');
    expect(
      result,
      orderedEquals(expectedTight),
      reason: 'no padding byte (0xa5) may leak into the packed output, and pixel order must match the tight layout',
    );
    expect(result.any((byte) => byte == 0xa5), isFalse, reason: 'no 0xa5 padding byte may appear anywhere in the output');

    // The source plane on the constructed image must not be mutated by the call.
    expect(image.yPlane.bytes, orderedEquals(paddedSnapshot));
  });

  testWidgets('toBgra8888 on a tight BGRA plane (rowStride == width*4) returns the tight bytes unchanged', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    const width = 4;
    const height = 6;
    const tightRowStride = width * 4;

    final expectedTight = _buildTightBgraPattern(width, height);
    final tightPlane = _plane(expectedTight, height: height, rowStride: tightRowStride, usefulRowBytes: tightRowStride);
    final tightSnapshot = Uint8List.fromList(tightPlane.bytes);

    final image = YuvImage.bgra(width, height, planes: <YuvPlane>[tightPlane]);

    final result = image.toBgra8888();

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
/// `test/reference_native_conversions_test.dart`'s `_plane` helper.
YuvPlane _plane(
  Uint8List tight, {
  required int height,
  required int rowStride,
  required int usefulRowBytes,
}) {
  final bytes = Uint8List(height * rowStride)..fillRange(0, height * rowStride, 0xa5);
  for (int row = 0; row < height; row++) {
    final destination = row * rowStride;
    final source = row * usefulRowBytes;
    bytes.setRange(destination, destination + usefulRowBytes, tight, source);
  }
  return YuvPlane(height, rowStride, 4, bytes);
}
