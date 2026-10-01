@Tags(['probe'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'probe_selection.dart';
import 'probe_support.dart';

const _dartOperationsDefined = bool.hasEnvironment('PROBE_OPS');
const _dartOperations = String.fromEnvironment('PROBE_OPS');
const _dartFormatsDefined = bool.hasEnvironment('PROBE_FORMATS');
const _dartFormats = String.fromEnvironment('PROBE_FORMATS');

void main() {
  test('native operation matrix matches the exact golden', () async {
    final document =
        jsonDecode(await File('test/probe/golden.json').readAsString())
            as Map<String, dynamic>;
    expect(document['schema'], 1);
    final golden = document['cases'] as Map<String, dynamic>;
    final selectors = probeSelectorsForVm(
      dartOperationsDefined: _dartOperationsDefined,
      dartOperations: _dartOperations,
      dartFormatsDefined: _dartFormatsDefined,
      dartFormats: _dartFormats,
      environment: Platform.environment,
    );
    final selection = ProbeSelection.fromSelectors(
      operationSelector: selectors.operations,
      formatSelector: selectors.formats,
    );
    final recordMode = Platform.environment['PROBE_RECORD'];
    if (recordMode != null && selection.hasSelectors) {
      throw ArgumentError(
        'PROBE_RECORD cannot be used with PROBE_OPS or PROBE_FORMATS.',
      );
    }
    if (recordMode != null) {
      final changed = await recordProbeGolden(golden, mode: recordMode);
      if (changed) {
        await File('test/probe/golden.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(document)}\n',
        );
      }
    }
    expectProbeGoldenCaseIdsExact(golden);
    debugPrint(selection.scope);
    final inputMismatches = probeInputMismatches(
      golden,
      caseIds: selection.caseIds,
    );
    expect(
      inputMismatches,
      isEmpty,
      reason:
          'Probe input generator diverges on this platform:\n${inputMismatches.take(20).join('\n')}',
    );
    expectProbeMismatchesEmpty(
      await probeMismatches(golden, caseIds: selection.caseIds),
    );

    final negativeGolden = {
      ...golden,
      selection.caseIds.first: 'intentionally-wrong',
    };
    final negativeControl = await probeMismatches(
      negativeGolden,
      caseIds: [selection.caseIds.first],
    );
    expect(negativeControl, hasLength(1));
    expect(negativeControl.single, startsWith('${selection.caseIds.first}:'));
  });

  test('recording appends missing values and overwrites only explicitly', () {
    final golden = <String, dynamic>{'existing': 'old'};
    final actual = <String, dynamic>{'existing': 'new', 'missing': 'new'};

    expect(recordProbeGoldenValues(golden, actual, mode: '1'), isTrue);
    expect(golden, {'existing': 'old', 'missing': 'new'});

    expect(recordProbeGoldenValues(golden, actual, mode: 'overwrite'), isTrue);
    expect(golden, actual);
  });
}
