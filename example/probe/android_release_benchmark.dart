import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yuv_ffi/yuv_ffi.dart';

import '../../test/probe/probe_runner.dart';
import '../../test/probe/probe_scenarios.dart';

const _gitSha = String.fromEnvironment('RA26_GIT_SHA');
const _runId = String.fromEnvironment('RA26_RUN_ID');
const _hostId = String.fromEnvironment('RA26_HOST_ID');
const _baselineDocument = String.fromEnvironment('RA26_BASELINES');
const _warmups = int.fromEnvironment('RA26_WARMUPS', defaultValue: 3);
const _samples = int.fromEnvironment('RA26_SAMPLES', defaultValue: 9);
const _strict = bool.fromEnvironment('RA26_STRICT');
const _cooldownSeconds = int.fromEnvironment('RA26_COOLDOWN_SECONDS', defaultValue: 30);
const _sizes = <(int, int)>[(1920, 1080), (720, 360)];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _AndroidReleaseBenchmarkApp());

  final document = <String, Object?>{
    'schema': 1,
    'status': 'FAIL',
    'gitSha': _gitSha,
    'runId': _runId,
    'hostId': _hostId,
    'buildMode': 'release',
    'environment': {'valid': true},
    'runs': <Object?>[],
  };

  try {
    _validateConfiguration();
    await YuvFfi.initialize();
    final runs = await _runScenarios(_loadBaselines(_baselineDocument));
    _validateRuns(runs);
    document
      ..['status'] = 'PASS'
      ..['runs'] = runs.map((run) => run.toJson()).toList(growable: false);
  } catch (error) {
    document['error'] = '$error';
  }

  final runs = document['runs'] as List<Object?>;
  for (final run in runs) {
    // Each result is smaller than one Android log record. The host reads all
    // 24 records and verifies their hashes before accepting the summary.
    // ignore: avoid_print
    print('RA26_ANDROID_RUN ${jsonEncode(run)}');
  }
  final summary = <String, Object?>{
    ...document,
    'scenarioCount': runs.length,
    'sampleCount': _samples,
    'runsSha256': sha256.convert(utf8.encode(jsonEncode(runs))).toString(),
  }..remove('runs');
  // ignore: avoid_print
  print('RA26_ANDROID_RESULT ${jsonEncode(summary)}');
}

void _validateConfiguration() {
  if (!kReleaseMode) {
    throw StateError('Android benchmark must run in release mode.');
  }
  if (!defaultTargetPlatform.name.contains('android')) {
    throw StateError('Android benchmark ran on ${defaultTargetPlatform.name}.');
  }
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(_gitSha)) {
    throw StateError('RA26_GIT_SHA must be a full lowercase Git SHA.');
  }
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(_runId)) {
    throw StateError('RA26_RUN_ID must be a 32-character lowercase run ID.');
  }
  if (!RegExp(r'^android-.+-arm64-v8a-release$').hasMatch(_hostId)) {
    throw StateError('RA26_HOST_ID must identify an Android arm64 release host.');
  }
  if (_warmups < 0 || _samples <= 0 || _cooldownSeconds < 0) {
    throw StateError('Invalid warmup, sample, or cooldown count.');
  }
}

Map<String, ProbeBaseline> _loadBaselines(String encoded) {
  if (encoded.isEmpty) return const {};
  final decoded = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
  final document = jsonDecode(decoded);
  if (document is! Map<String, dynamic> || document['schema'] != 1 || document['hostId'] != _hostId || document['runs'] is! List<dynamic>) {
    throw StateError('RA26_BASELINES has an unsupported result schema.');
  }
  final baselines = <String, ProbeBaseline>{};
  for (final entry in document['runs'] as List<dynamic>) {
    if (entry is! Map<String, dynamic> || entry['id'] is! String || baselines.containsKey(entry['id'])) {
      throw StateError('RA26_BASELINES has an invalid or duplicate scenario.');
    }
    baselines[entry['id'] as String] = ProbeBaseline.fromJson(entry);
  }
  if (baselines.length != probeScenarios.length * _sizes.length) {
    throw StateError('RA26_BASELINES must contain all ${probeScenarios.length * _sizes.length} scenarios.');
  }
  return baselines;
}

Future<List<ProbeRun>> _runScenarios(Map<String, ProbeBaseline> baselines) async {
  final config = ProbeTimingConfig(warmups: _warmups, samples: _samples, strict: _strict);
  final runs = <ProbeRun>[];
  for (var index = 0; index < probeScenarios.length; index++) {
    final scenario = probeScenarios[index];
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
    if (_cooldownSeconds > 0 && index + 1 < probeScenarios.length) {
      await Future<void>.delayed(Duration(seconds: _cooldownSeconds));
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
  final unstableHashes = runs.where((run) => run.sampleHashes.any((hash) => hash != run.hash)).toList(growable: false);
  if (unstableHashes.isNotEmpty) {
    throw StateError('${unstableHashes.length} benchmark scenarios changed their post-timer result hash.');
  }
}

class _AndroidReleaseBenchmarkApp extends StatelessWidget {
  const _AndroidReleaseBenchmarkApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('Android release benchmark is running.'))),
  );
}
