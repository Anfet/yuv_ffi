import 'dart:developer' as developer;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'helpers/shader_probe_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('matches CPU conversion across formats, sizes, orientations, padding and scale', (tester) async {
    await YuvFfi.initialize();
    final renderer = await YuvFrameRenderer.load();
    expect(renderer.hasShader, isTrue);
    final maximumByCase = await runShaderProbeCases(renderer);
    for (final entry in maximumByCase.entries) {
      expect(entry.value, lessThanOrEqualTo(1), reason: entry.key);
    }
    for (final entry in maximumByCase.entries.take(4)) {
      developer.log('SHADER PROBE size=${entry.key} max_diff=${entry.value}', name: 'yuv_ffi');
    }
    developer.log(
      'SHADER PROBE padding=${maximumByCase['padding']} scale_x2=${maximumByCase['scale_x2']} contain=${maximumByCase['contain']}',
      name: 'yuv_ffi',
    );
    renderer.dispose();
  });
}
