@Tags(['probe'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import 'probe_runner.dart';
import 'probe_scenarios.dart';

const _sizes = <(int, int)>[(1920, 1080), (720, 360)];

void main() {
  test(
    'performance scenarios report correctness hashes and timing verdicts',
    () async {
      final environment = Platform.environment;
      final config = ProbeTimingConfig(
        warmups: int.parse(environment['PROBE_WARMUPS'] ?? '3'),
        samples: int.parse(environment['PROBE_SAMPLES'] ?? '9'),
        strict: environment['PROBE_STRICT'] == '1',
        injectedDelay: Duration(milliseconds: int.parse(environment['PROBE_INJECT_DELAY_MS'] ?? '0')),
      );
      final selectedOperations = _selectedOperations(environment['PROBE_OPS']);
      final baselinePath = environment['PROBE_BASELINE_PATH'];
      final baselineDocument = baselinePath == null ? null : _readJson(File(baselinePath));
      final baselineScenarios = baselineDocument?['scenarios'] as Map<String, dynamic>? ?? const {};

      await YuvFfi.initialize();
      final runs = <ProbeRun>[];
      for (final scenario in probeScenarios.where((scenario) => selectedOperations.contains(scenario.operation.name))) {
        for (final (width, height) in _sizes) {
          final id = '${scenario.operation.name}/${scenario.name}/${width}x$height';
          final baseline = switch (baselineScenarios[id]) {
            final Map<String, dynamic> entry => ProbeBaseline.fromJson(entry),
            _ => null,
          };
          final run = runProbe(
            operation: scenario.operation.name,
            scenario: scenario.name,
            width: width,
            height: height,
            prepare: () => scenario.prepare(width, height),
            config: config,
            baseline: baseline,
          );
          runs.add(run);
          // ignore: avoid_print
          print(run.line);
        }
      }

      final document = <String, Object?>{
        'schema': 1,
        'status': runs.any((run) => run.verdict == 'FAIL') ? 'FAIL' : 'PASS',
        'hostId': environment['PROBE_HOST_ID'],
        'buildMode': environment['PROBE_BUILD_MODE'] ?? 'unknown',
        'environment': {'valid': environment['PROBE_ENV_VALID'] == '1', 'details': environment['PROBE_ENV_DETAILS']},
        'runs': runs.map((run) => run.toJson()).toList(growable: false),
      };
      final resultPath = environment['PROBE_RESULT_PATH'];
      if (resultPath != null) {
        final resultFile = File(resultPath);
        await resultFile.parent.create(recursive: true);
        await resultFile.writeAsString('${const JsonEncoder.withIndent('  ').convert(document)}\n');
      }
      if (environment['PROBE_RECORD'] == '1') {
        if (baselinePath == null) throw StateError('PROBE_BASELINE_PATH is required with PROBE_RECORD=1');
        final recordFile = File(baselinePath);
        await recordFile.parent.create(recursive: true);
        final recorded = <String, Object>{
          'schema': 1,
          'hostId': environment['PROBE_HOST_ID'] ?? 'unknown',
          'buildMode': environment['PROBE_BUILD_MODE'] ?? 'unknown',
          'scenarios': {
            for (final run in runs) run.id: ProbeBaseline(hash: run.hash, medianMicros: run.medianMicros, spreadPercent: run.spreadPercent).toJson(),
          },
        };
        await recordFile.writeAsString('${const JsonEncoder.withIndent('  ').convert(recorded)}\n');
      }

      expect(runs, isNotEmpty, reason: 'PROBE_OPS selected no known operations');
      expect(
        runs.where((run) => run.verdict == 'FAIL'),
        isEmpty,
        reason: runs.where((run) => run.verdict == 'FAIL').map((run) => run.line).join('\n'),
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: Platform.environment['PROBE_TIMING'] == '1' ? false : 'Set PROBE_TIMING=1 through tool/probe/run_windows.ps1 or run_android.ps1.',
  );
}

Set<String> _selectedOperations(String? raw) =>
    raw == null || raw.isEmpty ? {for (final scenario in probeScenarios) scenario.operation.name} : raw.split(',').toSet();

Map<String, dynamic>? _readJson(File file) {
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}
