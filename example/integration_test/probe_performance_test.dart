import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crypto/crypto.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import '../../test/probe/probe_runner.dart';
import '../../test/probe/probe_scenarios.dart';

const _runId = String.fromEnvironment('RA26_ANDROID_RUN_ID');
const _abi = String.fromEnvironment('RA26_ANDROID_ABI');
const _gitSha = String.fromEnvironment('RA26_GIT_SHA');
const _selectedOperations = String.fromEnvironment('RA26_OPS');
const _strict = bool.fromEnvironment('RA26_STRICT');
const _cooldownSeconds = int.fromEnvironment('RA26_COOLDOWN_SECONDS', defaultValue: 30);
const _warmups = int.fromEnvironment('RA26_WARMUPS', defaultValue: 3);
const _samples = int.fromEnvironment('RA26_SAMPLES', defaultValue: 9);
const _sizes = <(int, int)>[(1920, 1080), (720, 360)];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('profile benchmark reports a single complete structured verdict', (tester) async {
    final document = <String, Object?>{
      'schema': 1,
      'status': 'FAIL',
      'runId': _runId,
      'abi': _abi,
      'gitSha': _gitSha,
      'buildMode': 'profile',
      'environment': {'valid': true},
      'runs': <Object?>[],
    };

    try {
      _validateConfiguration();
      await YuvFfi.initialize();
      final selected = _parseSelectedOperations();
      final selectedScenarios = probeScenarios.where((scenario) => selected.contains(scenario.operation.name)).toList(growable: false);
      final runs = <ProbeRun>[];
      final config = ProbeTimingConfig(warmups: _warmups, samples: _samples, strict: _strict);
      for (var scenarioIndex = 0; scenarioIndex < selectedScenarios.length; scenarioIndex++) {
        final scenario = selectedScenarios[scenarioIndex];
        for (final (width, height) in _sizes) {
          final run = runProbe(
            operation: scenario.operation.name,
            scenario: scenario.name,
            width: width,
            height: height,
            prepare: () => scenario.prepare(width, height),
            config: config,
          );
          runs.add(run);
          // ignore: avoid_print
          print(run.line);
        }
        if (_cooldownSeconds > 0 && scenarioIndex + 1 < selectedScenarios.length) {
          await Future<void>.delayed(Duration(seconds: _cooldownSeconds));
        }
      }
      _validateRuns(runs, selected.length * _sizes.length);
      document
        ..['status'] = 'PASS'
        ..['runs'] = runs.map((run) => run.toJson()).toList(growable: false);
    } catch (error) {
      document['error'] = '$error';
    }

    final marker = <String, Object?>{
      ...document,
      'scenarioCount': (document['runs'] as List<Object?>).length,
      'sampleCount': _samples,
      'runsSha256': sha256.convert(utf8.encode(jsonEncode(document['runs']))).toString(),
    }..remove('runs');
    // Android logcat truncates a full 24-case JSON value. The host combines
    // this compact authenticated summary with the 24 PROBE lines.
    // ignore: avoid_print
    print('RA26_ANDROID_RESULT ${jsonEncode(marker)}');
    expect(document['status'], 'PASS', reason: document['error'] as String?);
  }, timeout: const Timeout(Duration(minutes: 20)));
}

void _validateConfiguration() {
  if (!kProfileMode) {
    throw StateError('Android benchmark must run in profile mode.');
  }
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(_runId)) {
    throw StateError('RA26_ANDROID_RUN_ID must be a 32-character lowercase run ID.');
  }
  if (_abi != 'arm64-v8a' && _abi != 'armeabi-v7a') {
    throw StateError('RA26_ANDROID_ABI must be arm64-v8a or armeabi-v7a.');
  }
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(_gitSha)) {
    throw StateError('RA26_GIT_SHA must be a full lowercase Git SHA.');
  }
  if (_cooldownSeconds < 0 || _warmups < 0 || _samples <= 0) {
    throw StateError('Invalid cooldown, warmup, or sample count.');
  }
}

Set<String> _parseSelectedOperations() {
  if (_selectedOperations.isEmpty) return {for (final scenario in probeScenarios) scenario.operation.name};
  final selected = _selectedOperations.split(',').where((name) => name.isNotEmpty).toSet();
  final known = {for (final scenario in probeScenarios) scenario.operation.name};
  final unknown = selected.difference(known);
  if (unknown.isNotEmpty) {
    throw StateError('Unknown benchmark operations: ${unknown.join(', ')}');
  }
  if (selected.isEmpty) {
    throw StateError('RA26_OPS selected no benchmark operations.');
  }
  return selected;
}

void _validateRuns(List<ProbeRun> runs, int expectedCount) {
  if (runs.length != expectedCount) {
    throw StateError('Expected $expectedCount benchmark runs, found ${runs.length}.');
  }
  final failures = runs.where((run) => run.verdict != 'PASS').toList(growable: false);
  if (failures.isNotEmpty) {
    throw StateError('${failures.length} benchmark failures:\n${failures.map((run) => run.line).join('\n')}');
  }
  final unstableHashes = runs.where((run) => run.sampleHashes.any((sampleHash) => sampleHash != run.hash)).toList(growable: false);
  if (unstableHashes.isNotEmpty) {
    throw StateError('${unstableHashes.length} benchmark scenarios changed post-timer output.');
  }
}
