@Tags(['probe'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'cases.dart';
import 'probe_support.dart';

void main() {
  test('native operation matrix matches the exact golden', () async {
    final document =
        jsonDecode(await File('test/probe/golden.json').readAsString())
            as Map<String, dynamic>;
    expect(document['schema'], 1);
    final golden = document['cases'] as Map<String, dynamic>;
    final recordMode = Platform.environment['PROBE_RECORD'];
    if (recordMode != null) {
      final changed = await recordProbeGolden(golden, mode: recordMode);
      if (changed) {
        await File('test/probe/golden.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(document)}\n',
        );
      }
    }
    expectProbeGoldenCaseIdsExact(golden);
    final inputMismatches = probeInputMismatches(golden);
    expect(
      inputMismatches,
      isEmpty,
      reason:
          'Probe input generator diverges on this platform:\n${inputMismatches.take(20).join('\n')}',
    );
    expectProbeMismatchesEmpty(await probeMismatches(golden));

    final negativeGolden = {
      ...golden,
      probeCaseIds.first: 'intentionally-wrong',
    };
    final negativeControl = await probeMismatches(
      negativeGolden,
      caseIds: [probeCaseIds.first],
    );
    expect(negativeControl, hasLength(1));
    expect(negativeControl.single, startsWith('${probeCaseIds.first}:'));
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
