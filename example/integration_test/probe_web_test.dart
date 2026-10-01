import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/probe/probe_selection.dart';
import 'helpers/probe/probe_support.dart';

const _operationsDefined = bool.hasEnvironment('PROBE_OPS');
const _operations = String.fromEnvironment('PROBE_OPS');
const _formatsDefined = bool.hasEnvironment('PROBE_FORMATS');
const _formats = String.fromEnvironment('PROBE_FORMATS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Web operation matrix matches the exact golden', (tester) async {
    final document = await rootBundle.loadString('assets/probe/golden.json');
    final golden = decodeProbeGolden(document);
    expectProbeGoldenCaseIdsExact(golden);
    final selection = ProbeSelection.fromSelectors(
      operationSelector: _operationsDefined ? _operations : null,
      formatSelector: _formatsDefined ? _formats : null,
    );
    debugPrint(selection.scope);
    final inputMismatches = probeInputMismatches(golden, caseIds: selection.caseIds);
    expect(inputMismatches, isEmpty, reason: 'Probe input generator diverges on this platform:\n${inputMismatches.take(20).join('\n')}');
    final mismatches = await probeMismatches(golden, caseIds: selection.caseIds);
    expectProbeMismatchesEmpty(mismatches);
    debugPrint('Web probe matrix passed: ${selection.caseIds.length} cases');
  });
}
