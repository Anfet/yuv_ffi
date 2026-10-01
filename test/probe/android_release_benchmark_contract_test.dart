@Tags(['probe'])
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final entrypoint = File('example/probe/android_release_benchmark.dart').readAsStringSync();
  final runner = File('tool/probe/run_android.ps1').readAsStringSync();

  test('Android benchmark requires AOT release and emits every retained run', () {
    expect(entrypoint, contains('if (!kReleaseMode)'));
    expect(entrypoint, contains("print('RA26_ANDROID_RUN"));
    expect(entrypoint, contains("print('RA26_ANDROID_RESULT"));
    expect(entrypoint, contains('probeScenarios.length * _sizes.length'));
    expect(entrypoint, contains('sampleHashes.any((hash) => hash != run.hash)'));
  });

  test('Android host runner verifies the release package and all 24 run records', () {
    expect(runner, contains("'build', 'apk', '--release'"));
    expect(runner, contains('RA-26 package config resolved yuv_ffi to'));
    expect(runner, contains('RA26_ANDROID_RUN'));
    expect(runner, contains('expected 24 RA26_ANDROID_RUN records'));
    expect(runner, contains('Android release benchmark run integrity failed'));
    expect(runner, contains('Out-String -Width 32767'));
    expect(runner, contains('@(Read-JsonRecords'));
    expect(runner, contains(r'$hostSummary | ConvertTo-Json -Compress'));
  });
}
