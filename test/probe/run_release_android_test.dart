import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory worktree;
  late String gitSha;
  const runId = '0123456789abcdef0123456789abcdef';

  setUpAll(() async {
    worktree = Directory('${Directory.systemTemp.path}\\yuv-ffi-ra25-script-${DateTime.now().microsecondsSinceEpoch}');
    await _run('git', ['worktree', 'add', '--detach', worktree.path, 'HEAD']);

    final sourceScript = File('tool/probe/run_release_android.ps1');
    final worktreeScript = File('${worktree.path}\\tool\\probe\\run_release_android.ps1');
    await sourceScript.copy(worktreeScript.path);
    await _run('git', ['-C', worktree.path, 'add', 'tool/probe/run_release_android.ps1']);
    await _run('git', [
      '-C',
      worktree.path,
      '-c',
      'user.name=RA-25 test',
      '-c',
      'user.email=ra25-test@example.invalid',
      'commit',
      '-m',
      'Validated RA-25 script fixture',
    ]);
    gitSha = (await _run('git', ['-C', worktree.path, 'rev-parse', 'HEAD'])).stdout.toString().trim();
  });

  tearDownAll(() async {
    await _run('git', ['worktree', 'remove', '--force', worktree.path]);
  });

  test('accepts one complete RA25_RESULT marker from a clean matching checkout', () async {
    final logcat = await _writeLogcat('valid', _validMarker(gitSha, runId));
    addTearDown(logcat.delete);

    final result = await _validate(worktree.path, gitSha, runId, logcat);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('RA25_LOGCAT_RESULT'));
  });

  test('rejects an expected SHA that differs from the actual checkout', () async {
    final logcat = await _writeLogcat('wrong-sha', _validMarker(gitSha, runId));
    addTearDown(logcat.delete);

    final result = await _validate(worktree.path, '0000000000000000000000000000000000000000', runId, logcat);

    expect(result.exitCode, isNot(0));
    expect('${result.stdout}\n${result.stderr}', contains('does not match actual source checkout HEAD'));
  });

  test('rejects a dirty checkout before it can build an APK', () async {
    final dirtyFile = File('${worktree.path}\\ra25-dirty-check.txt');
    await dirtyFile.writeAsString('dirty');
    addTearDown(dirtyFile.delete);
    final logcat = await _writeLogcat('dirty', _validMarker(gitSha, runId));
    addTearDown(logcat.delete);

    final result = await _validate(worktree.path, gitSha, runId, logcat);

    expect(result.exitCode, isNot(0));
    expect('${result.stdout}\n${result.stderr}', contains('requires a clean source checkout before the release APK build'));
  });

  test('rejects a malformed marker even when a valid marker follows it', () async {
    final logcat = await _writeLogcat('duplicate', 'RA25_RESULT malformed\n${_validMarker(gitSha, runId)}');
    addTearDown(logcat.delete);

    final result = await _validate(worktree.path, gitSha, runId, logcat);

    expect(result.exitCode, isNot(0));
    expect('${result.stdout}\n${result.stderr}', contains('Expected exactly one RA25_RESULT logcat marker, found 2'));
  });

  test('rejects a missing marker after the logcat timeout', () async {
    final logcat = await _writeLogcat('missing-after-timeout', 'unrelated logcat output');
    addTearDown(logcat.delete);

    final elapsed = Stopwatch()..start();
    final result = await _validate(worktree.path, gitSha, runId, logcat, timeoutSeconds: 2);
    elapsed.stop();

    expect(result.exitCode, isNot(0));
    expect(elapsed.elapsed, greaterThanOrEqualTo(const Duration(seconds: 2)));
    expect('${result.stdout}\n${result.stderr}', contains('Expected exactly one RA25_RESULT logcat marker, found 0'));
  });

  test('rejects a malformed marker without a valid result', () async {
    final logcat = await _writeLogcat('malformed-only', 'RA25_RESULT {not-json}');
    addTearDown(logcat.delete);

    final result = await _validate(worktree.path, gitSha, runId, logcat);

    expect(result.exitCode, isNot(0));
    expect('${result.stdout}\n${result.stderr}', contains('malformed JSON'));
  });

  test('rejects duplicate valid markers', () async {
    final marker = _validMarker(gitSha, runId);
    final logcat = await _writeLogcat('duplicate-valid', '$marker\n$marker');
    addTearDown(logcat.delete);

    final result = await _validate(worktree.path, gitSha, runId, logcat);

    expect(result.exitCode, isNot(0));
    expect('${result.stdout}\n${result.stderr}', contains('Expected exactly one RA25_RESULT logcat marker, found 2'));
  });

  test('rejects a marker with a wrong runId', () async {
    await _expectStrictRejection(worktree, gitSha, runId, 'wrong-run-id', _validMarker(gitSha, 'fedcba9876543210fedcba9876543210'));
  });

  test('rejects a marker with a wrong ABI', () async {
    await _expectStrictRejection(worktree, gitSha, runId, 'wrong-abi', _validMarker(gitSha, runId, abi: 'armeabi-v7a'));
  });

  test('rejects a marker with a wrong case count', () async {
    await _expectStrictRejection(worktree, gitSha, runId, 'wrong-count', _validMarker(gitSha, runId, caseCount: 1187));
  });

  test('rejects a marker with a wrong schema type', () async {
    await _expectStrictRejection(worktree, gitSha, runId, 'wrong-schema', _validMarker(gitSha, runId, schema: '1'));
  });

  test('rejects a marker with a wrong schema version', () async {
    await _expectStrictRejection(worktree, gitSha, runId, 'wrong-schema-version', _validMarker(gitSha, runId, schema: 2));
  });

  test('rejects lowercase PASS fields', () async {
    await _expectStrictRejection(worktree, gitSha, runId, 'wrong-case', _validMarker(gitSha, runId, smoke: 'pass', probe: 'pass'));
  });
}

Future<void> _expectStrictRejection(Directory worktree, String gitSha, String runId, String name, String marker) async {
  final logcat = await _writeLogcat(name, marker);
  addTearDown(logcat.delete);

  final result = await _validate(worktree.path, gitSha, runId, logcat);

  expect(result.exitCode, isNot(0));
  expect('${result.stdout}\n${result.stderr}', contains('failed strict validation'));
}

String _validMarker(
  String gitSha,
  String runId, {
  Object schema = 1,
  String abi = 'arm64-v8a',
  String smoke = 'PASS',
  String probe = 'PASS',
  Object caseCount = 1188,
}) =>
    'RA25_RESULT '
    '{"schema":${jsonEncode(schema)},"gitSha":"$gitSha","runId":"$runId","abi":"$abi",'
    '"smoke":"$smoke","probe":"$probe","caseCount":${jsonEncode(caseCount)}}';

Future<File> _writeLogcat(String name, String contents) async {
  final file = File('${Directory.systemTemp.path}\\yuv-ffi-ra25-$name-${DateTime.now().microsecondsSinceEpoch}.log');
  await file.writeAsString(contents);
  return file;
}

Future<ProcessResult> _validate(String worktreePath, String gitSha, String runId, File logcat, {int timeoutSeconds = 300}) => Process.run('pwsh', [
  '-NoProfile',
  '-File',
  '$worktreePath\\tool\\probe\\run_release_android.ps1',
  '-GitSha',
  gitSha,
  '-RunId',
  runId,
  '-TimeoutSeconds',
  '$timeoutSeconds',
  '-ValidateLogcatPath',
  logcat.path,
], workingDirectory: worktreePath);

Future<ProcessResult> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError('$executable ${arguments.join(' ')} failed:\n${result.stdout}\n${result.stderr}');
  }
  return result;
}
