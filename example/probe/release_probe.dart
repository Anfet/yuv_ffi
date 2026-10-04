import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../tool/probe/release_probe_core.dart';

const _gitSha = String.fromEnvironment('RA25_GIT_SHA');
const _runId = String.fromEnvironment('RA25_RUN_ID');
const _abi = String.fromEnvironment('RA25_EXPECTED_ABI');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ReleaseProbeApp());

  final result = <String, Object>{'schema': 1, 'gitSha': _gitSha, 'runId': _runId, 'abi': _abi, 'smoke': 'FAIL', 'probe': 'FAIL', 'caseCount': 0};

  try {
    _validateConfiguration();
    final goldenDocument = await rootBundle.loadString('assets/probe/golden.json');
    final probe = await runReleaseProbe(goldenDocument);
    result['smoke'] = probe.smoke;
    result['probe'] = probe.probe;
    result['caseCount'] = probe.caseCount;
  } catch (error) {
    result['error'] = '$error';
  }

  // The host accepts this sole marker from Android logcat as the release verdict.
  // ignore: avoid_print
  print('RA25_RESULT ${jsonEncode(result)}');
}

void _validateConfiguration() {
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(_gitSha)) {
    throw StateError('RA25_GIT_SHA must be a full lowercase Git SHA.');
  }
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(_runId)) {
    throw StateError('RA25_RUN_ID must be a 32-character lowercase run ID.');
  }
  if (_abi != 'arm64-v8a' && _abi != 'armeabi-v7a') {
    throw StateError('RA25_EXPECTED_ABI must be arm64-v8a or armeabi-v7a.');
  }
}

class _ReleaseProbeApp extends StatelessWidget {
  const _ReleaseProbeApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(body: Center(child: Text('Release probe is running.'))),
  );
}
