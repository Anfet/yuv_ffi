import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uses the BGRA fallback in CanvasKit', (tester) async {
    await YuvFfi.initialize();
    final renderer = await YuvFrameRenderer.load();
    developer.log('SHADER PROBE web has_shader=${renderer.hasShader}', name: 'yuv_ffi');
    expect(renderer.hasShader, isFalse);
    renderer.dispose();
  });
}
