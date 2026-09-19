import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

/// Probe for YUV-02: can the WASM runtime load at all in a real browser?
///
/// `flutter test --platform chrome` serves no asset bundle — its server answers
/// `/static/index.html` and 404s everything else, including
/// `assets/packages/yuv_ffi/assets/wasm/yuv_ffi.js` and `AssetManifest.json` —
/// so the loader's script tag can never resolve there. This runs against a real
/// built application instead, where those assets exist.
///
/// It deliberately proves only the bootstrap. The full reference matrix remains
/// YUV-12 work and must use this same harness.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Web WASM runtime initializes and converts a frame', (tester) async {
    expect(kIsWeb, isTrue, reason: 'This required gate must run in a browser.');

    await YuvFfi.ensureInitialized();

    // This crosses the asset-loaded module boundary three times: RGBA -> BGRA,
    // BGRA -> I420, and I420 -> BGRA. A module that only loaded but could not
    // execute a conversion fails this test.
    final image = YuvImage.bgra(2, 2)
      ..fromRgba8888(
        Uint8List.fromList(<int>[
          255, 0, 0, 255,
          0, 255, 0, 255,
          0, 0, 255, 255,
          255, 255, 255, 255,
        ]),
      )
      ..toYuvI420();

    final bytes = image.toBgra8888();

    expect(bytes, hasLength(2 * 2 * 4));
    expect(bytes.any((byte) => byte != 0), isTrue);
  });
}
