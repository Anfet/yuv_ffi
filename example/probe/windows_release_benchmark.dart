import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import '../../test/probe/probe_runner.dart';
import '../../test/probe/probe_scenarios.dart';

const _gitSha = String.fromEnvironment('RA26_GIT_SHA');
const _runId = String.fromEnvironment('RA26_RUN_ID');
const _resultPath = String.fromEnvironment('RA26_RESULT_PATH');
const _hostId = String.fromEnvironment('RA26_HOST_ID');
const _baselinePath = String.fromEnvironment('RA26_BASELINE_PATH');
const _warmups = int.fromEnvironment('RA26_WARMUPS', defaultValue: 3);
const _samples = int.fromEnvironment('RA26_SAMPLES', defaultValue: 9);
const _strict = bool.fromEnvironment('RA26_STRICT');
const _sizes = <(int, int)>[(1920, 1080), (720, 360)];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ReleaseBenchmarkApp());

  final document = <String, Object?>{
    'schema': 1,
    'status': 'FAIL',
    'gitSha': _gitSha,
    'runId': _runId,
    'hostId': _hostId,
    'buildMode': 'release',
    'environment': {'valid': false},
    'runs': <Object?>[],
  };

  try {
    _validateConfiguration();
    await YuvFfi.initialize();
    final baselines = _loadBaselines(_baselinePath);
    final runs = _runScenarios(baselines);
    _validateRuns(runs);
    document
      ..['status'] = 'PASS'
      ..['environment'] = {'valid': true}
      ..['runs'] = runs.map((run) => run.toJson()).toList(growable: false);
  } catch (error) {
    document['error'] = '$error';
  }

  try {
    await _writeAtomically(File(_resultPath), document);
  } catch (error) {
    // A missing result is itself a failed host validation; leave this concise
    // marker for an interactive release-smoke invocation.
    // ignore: avoid_print
    print('RA26_RESULT_WRITE_FAILED $error');
    exit(1);
  }
  // ignore: avoid_print
  print('RA26_RESULT ${jsonEncode(document)}');
  exit(document['status'] == 'PASS' ? 0 : 1);
}

void _validateConfiguration() {
  if (!kReleaseMode) {
    throw StateError('Windows benchmark must run in release mode.');
  }
  if (!Platform.isWindows) {
    throw StateError('Windows benchmark ran on ${Platform.operatingSystem}.');
  }
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(_gitSha)) {
    throw StateError('RA26_GIT_SHA must be a full lowercase Git SHA.');
  }
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(_runId)) {
    throw StateError('RA26_RUN_ID must be a 32-character lowercase run ID.');
  }
  if (_hostId.isEmpty || !RegExp(r'^windows-.+-x64-release$').hasMatch(_hostId)) {
    throw StateError('RA26_HOST_ID must identify a Windows x64 release host.');
  }
  if (_warmups < 0 || _samples <= 0) {
    throw StateError('RA26_WARMUPS must be non-negative and RA26_SAMPLES positive.');
  }
  final resultFile = File(_resultPath);
  if (!resultFile.isAbsolute || !resultFile.path.toLowerCase().endsWith('$_runId.json')) {
    throw StateError('RA26_RESULT_PATH must be an absolute unique path ending in $_runId.json.');
  }
  if (resultFile.existsSync()) {
    throw StateError('RA26_RESULT_PATH already exists: $_resultPath');
  }
}

Map<String, ProbeBaseline> _loadBaselines(String path) {
  if (path.isEmpty) return const {};
  final baselineFile = File(path);
  if (!baselineFile.existsSync()) {
    throw StateError('RA26_BASELINE_PATH does not exist: $path');
  }
  final document = jsonDecode(baselineFile.readAsStringSync());
  if (document is! Map<String, dynamic> || document['schema'] != 1 || document['runs'] is! List<dynamic>) {
    throw StateError('RA26_BASELINE_PATH has an unsupported result schema.');
  }
  final baselines = <String, ProbeBaseline>{};
  for (final entry in document['runs'] as List<dynamic>) {
    if (entry is! Map<String, dynamic> || entry['id'] is! String || baselines.containsKey(entry['id'])) {
      throw StateError('RA26_BASELINE_PATH has an invalid or duplicate scenario.');
    }
    baselines[entry['id'] as String] = ProbeBaseline.fromJson(entry);
  }
  if (baselines.length != probeScenarios.length * _sizes.length) {
    throw StateError('RA26_BASELINE_PATH must contain all ${probeScenarios.length * _sizes.length} scenarios.');
  }
  return baselines;
}

List<ProbeRun> _runScenarios(Map<String, ProbeBaseline> baselines) {
  final config = ProbeTimingConfig(warmups: _warmups, samples: _samples, strict: _strict);
  final runs = <ProbeRun>[];
  for (final scenario in probeScenarios) {
    for (final (width, height) in _sizes) {
      final id = '${scenario.operation.name}/${scenario.name}/${width}x$height';
      runs.add(
        runProbe(
          operation: scenario.operation.name,
          scenario: scenario.name,
          width: width,
          height: height,
          prepare: () => scenario.prepare(width, height),
          config: config,
          baseline: baselines[id],
        ),
      );
    }
  }
  return runs;
}

void _validateRuns(List<ProbeRun> runs) {
  final expected = probeScenarios.length * _sizes.length;
  if (runs.length != expected) {
    throw StateError('Expected $expected benchmark scenarios, found ${runs.length}.');
  }
  final failures = runs.where((run) => run.verdict != 'PASS').toList(growable: false);
  if (failures.isNotEmpty) {
    throw StateError('${failures.length} benchmark failures:\n${failures.map((run) => run.line).join('\n')}');
  }
  final unstableHashes = runs.where((run) => run.sampleHashes.any((sampleHash) => sampleHash != run.hash)).toList(growable: false);
  if (unstableHashes.isNotEmpty) {
    throw StateError('${unstableHashes.length} benchmark scenarios changed their post-timer result hash.');
  }
}

Future<void> _writeAtomically(File resultFile, Map<String, Object?> document) async {
  await resultFile.parent.create(recursive: true);
  final temporary = File('${resultFile.path}.$_runId.tmp');
  if (await temporary.exists()) {
    throw StateError('Temporary result path already exists: ${temporary.path}');
  }
  try {
    await temporary.writeAsString('${const JsonEncoder.withIndent('  ').convert(document)}\n');
    await temporary.rename(resultFile.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

class _ReleaseBenchmarkApp extends StatelessWidget {
  const _ReleaseBenchmarkApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('Windows release benchmark is running.'))),
  );
}
