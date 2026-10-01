@Tags(['contract'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<ProcessResult> _runReporter(String fixture) async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      Platform.environment['PATH']!
          .split(Platform.isWindows ? ';' : ':')
          .map((path) => path.replaceAll(RegExp(r'[/\\]bin$'), ''))
          .firstWhere((path) => File('$path/bin/flutter${Platform.isWindows ? '.bat' : ''}').existsSync());
  final dart = '$flutterRoot/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
  final process = await Process.start(dart, ['tool/ci/test_report.dart']);
  process.stdin.write(File('test/fixtures/test_report/$fixture.jsonl').readAsStringSync());
  await process.stdin.close();
  final stdout = await process.stdout.transform(systemEncoding.decoder).join();
  final stderr = await process.stderr.transform(systemEncoding.decoder).join();
  final exitCode = await process.exitCode;
  return ProcessResult(process.pid, exitCode, stdout, stderr);
}

void main() {
  test('successful run is concise and exits successfully', () async {
    final result = await _runReporter('success');

    expect(result.exitCode, 0);
    expect(result.stdout, contains('test/example_test.dart  Passed  1'));
    expect(result.stdout, contains('1/1 passed, 0 skipped, 0 failed'));
  });

  test('failed test prints its error block and exits unsuccessfully', () async {
    final result = await _runReporter('failure');

    expect(result.exitCode, 1);
    expect(result.stdout, contains('FAILED  adds values'));
    expect(result.stdout, contains('Expected: <2>'));
    expect(result.stdout, contains('test diagnostic'));
  });

  test('load error names its file and exits unsuccessfully', () async {
    final result = await _runReporter('load_error');

    expect(result.exitCode, 1);
    expect(result.stdout, contains('test/broken_test.dart  FAILED'));
    expect(result.stdout, contains('Expected a declaration'));
  });

  test('run with no tests exits unsuccessfully', () async {
    final result = await _runReporter('empty');

    expect(result.exitCode, 1);
    expect(result.stdout, contains('0/0 passed'));
  });
}
