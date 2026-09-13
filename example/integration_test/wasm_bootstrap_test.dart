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
/// It deliberately proves only the bootstrap. If this passes, the four suites in
/// `test/web/` can move here; if it fails, nothing else is worth porting yet.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the WASM runtime initializes from the app asset bundle', (tester) async {
    await YuvFfi.ensureInitialized();

    // A conversion is the cheapest end-to-end proof that the module is not just
    // loaded but callable: it crosses into WASM and back.
    final image = YuvImage.bgra(4, 4);
    final bytes = image.toBgra8888();

    expect(bytes.length, 4 * 4 * 4);
  });
}
