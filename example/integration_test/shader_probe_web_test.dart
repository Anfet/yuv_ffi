import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'helpers/shader_probe_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('matches CPU conversion in CanvasKit', (tester) async {
    await YuvFfi.initialize();
    final renderer = await YuvFrameRenderer.load();
    developer.log('SHADER PROBE web has_shader=${renderer.hasShader}', name: 'yuv_ffi');
    expect(renderer.hasShader, isTrue);

    final maximumByCase = await runShaderProbeCases(renderer);
    for (final entry in maximumByCase.entries) {
      developer.log('SHADER PROBE web ${entry.key} max_diff=${entry.value}', name: 'yuv_ffi');
      expect(entry.value, lessThanOrEqualTo(1), reason: entry.key);
    }
    renderer.dispose();
  });
}
