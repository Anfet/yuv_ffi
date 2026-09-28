import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'cases.dart';
import 'probe_support.dart';
import 'probe_scenarios.dart';

void main() {
  test('every public operation has at least one correctness case', () {
    expect(_missingOperations(probeCaseIds), isEmpty);
  });

  test('omitting one operation file makes the coverage check fail', () {
    final withoutChromaSwap = probeCaseIds.where((id) => operationForCase(ProbeCase(id)) != YuvOperation.chromaSwap);
    expect(_missingOperations(withoutChromaSwap), contains(YuvOperation.chromaSwap));
  });

  test('every public operation has one performance scenario', () {
    expect({for (final scenario in probeScenarios) scenario.operation}, unorderedEquals(YuvOperation.values));
  });
}

Set<YuvOperation> _missingOperations(Iterable<String> caseIds) {
  final covered = {for (final id in caseIds) operationForCase(ProbeCase(id))};
  return YuvOperation.values.toSet().difference(covered);
}
