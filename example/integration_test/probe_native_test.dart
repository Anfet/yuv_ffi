import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/probe/cases.dart';
import 'helpers/probe/probe_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native operation matrix matches the exact golden', (tester) async {
    final document = await rootBundle.loadString('assets/probe/golden.json');
    final mismatches = await probeMismatches(decodeProbeGolden(document));
    expectProbeMismatchesEmpty(mismatches);
    debugPrint('Probe matrix passed: ${probeCaseIds.length} cases');
  });
}
