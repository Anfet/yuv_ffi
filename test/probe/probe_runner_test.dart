@Tags(['probe'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'probe_runner.dart';

void main() {
  const normal = ProbeTimingConfig(warmups: 0, samples: 3, strict: false);

  test('reports no baseline while still recording the correctness hash', () {
    final run = runProbe(operation: 'negate', scenario: 'synthetic', width: 2, height: 2, prepare: _prepared, config: normal);

    expect(run.verdict, 'PASS');
    expect(run.comparison, 'NO-BASELINE');
    expect(run.hash, 'correct-output');
    expect(run.sampleHashes, everyElement('correct-output'));
    expect(run.line, contains('PROBE negate synthetic 2x2 PASS'));
  });

  test('a post-timer result hash mismatch fails the run', () {
    var calls = 0;
    final run = runProbe(
      operation: 'negate',
      scenario: 'synthetic',
      width: 2,
      height: 2,
      prepare: () => PreparedProbeInvocation(call: () => ++calls, hash: (result) => result == 1 ? 'correct-output' : 'changed-output'),
      config: normal,
    );

    expect(run.verdict, 'FAIL');
    expect(run.comparison, 'SAMPLE-HASH-MISMATCH');
  });

  test('a mismatched correctness hash fails even without strict timing', () {
    final run = runProbe(
      operation: 'negate',
      scenario: 'synthetic',
      width: 2,
      height: 2,
      prepare: _prepared,
      config: normal,
      baseline: const ProbeBaseline(hash: 'wrong-output', medianMicros: 1, spreadPercent: 0),
    );

    expect(run.verdict, 'FAIL');
    expect(run.comparison, 'HASH-MISMATCH');
  });

  test('the test-only injected delay reports slower and strict mode fails', () {
    final run = runProbe(
      operation: 'negate',
      scenario: 'synthetic',
      width: 2,
      height: 2,
      prepare: _prepared,
      config: const ProbeTimingConfig(warmups: 0, samples: 3, strict: true, injectedDelay: Duration(milliseconds: 5)),
      baseline: const ProbeBaseline(hash: 'correct-output', medianMicros: 1, spreadPercent: 0),
    );

    expect(run.comparison, 'SLOWER');
    expect(run.verdict, 'FAIL');
  });

  test('a slower run stays informational outside strict mode', () {
    final run = runProbe(
      operation: 'negate',
      scenario: 'synthetic',
      width: 2,
      height: 2,
      prepare: _prepared,
      config: const ProbeTimingConfig(warmups: 0, samples: 3, strict: false, injectedDelay: Duration(milliseconds: 5)),
      baseline: const ProbeBaseline(hash: 'correct-output', medianMicros: 1, spreadPercent: 0),
    );

    expect(run.comparison, 'SLOWER');
    expect(run.verdict, 'PASS');
  });

  test('a matching baseline and repeated invocation stay in the same band', () {
    final first = runProbe(operation: 'negate', scenario: 'synthetic', width: 2, height: 2, prepare: _prepared, config: normal);
    final second = runProbe(
      operation: 'negate',
      scenario: 'synthetic',
      width: 2,
      height: 2,
      prepare: _prepared,
      config: normal,
      baseline: ProbeBaseline(hash: first.hash, medianMicros: first.medianMicros == 0 ? 1 : first.medianMicros, spreadPercent: 1000),
    );

    expect(second.comparison, 'SAME');
    expect(second.verdict, 'PASS');
  });
}

PreparedProbeInvocation _prepared() => PreparedProbeInvocation(call: () => 1, hash: (_) => 'correct-output');
