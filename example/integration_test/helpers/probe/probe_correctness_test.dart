@Tags(['probe'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'cases.dart';
import 'probe_support.dart';

void main() {
  test('native operation matrix matches the exact golden', () async {
    final document = jsonDecode(await File('test/probe/golden.json').readAsString()) as Map<String, dynamic>;
    expect(document['schema'], 1);
    final golden = document['cases'] as Map<String, dynamic>;
    expect(golden.keys, containsAll(probeCaseIds));
    expectProbeMismatchesEmpty(await probeMismatches(golden));

    final negativeGolden = {...golden, probeCaseIds.first: 'intentionally-wrong'};
    final negativeControl = await probeMismatches(negativeGolden, caseIds: [probeCaseIds.first]);
    expect(negativeControl, hasLength(1));
    expect(negativeControl.single, startsWith('${probeCaseIds.first}:'));
  });
}
