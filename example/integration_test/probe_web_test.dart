import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/probe/cases.dart';
import 'helpers/probe/probe_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Web operation matrix matches the exact golden', (tester) async {
    final document = await rootBundle.loadString('assets/probe/golden.json');
    final golden = decodeProbeGolden(document);
    final inputMismatches = probeInputMismatches(golden);
    expect(inputMismatches, isEmpty, reason: 'Probe input generator diverges on this platform:\n${inputMismatches.take(20).join('\n')}');
    final mismatches = await probeMismatches(golden);
    expectProbeMismatchesEmpty(mismatches);
    debugPrint('Web probe matrix passed: ${probeCaseIds.length} cases');
  });
}
