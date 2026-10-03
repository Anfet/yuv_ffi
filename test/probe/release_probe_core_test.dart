@Tags(['release'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/probe/release_probe_core.dart';

void main() {
  test('release probe core accepts every exact golden case', () async {
    final result = await runReleaseProbe(await File('test/probe/golden.json').readAsString());

    expect(result.smoke, 'PASS');
    expect(result.probe, 'PASS');
    expect(result.caseCount, releaseProbeCaseCount);
  });
}
