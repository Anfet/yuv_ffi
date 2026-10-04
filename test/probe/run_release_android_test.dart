@Tags(['release'])
library;

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

    final changedFiles = <String>[];
    for (final relativePath in ['tool/probe/run_release_android.ps1', 'tool/probe/release_android_versioning.ps1']) {
      final sourceFile = File(relativePath);
      final worktreeFile = File('${worktree.path}\\${relativePath.replaceAll('/', '\\')}');
      if (!await worktreeFile.exists() || await sourceFile.readAsString() != await worktreeFile.readAsString()) {
        await sourceFile.copy(worktreeFile.path);
        changedFiles.add(relativePath);
      }
    }
    if (changedFiles.isNotEmpty) {
      await _run('git', ['-C', worktree.path, 'add', ...changedFiles]);
      final stagedDiff = await Process.run('git', ['-C', worktree.path, 'diff', '--cached', '--quiet']);
      if (stagedDiff.exitCode == 1) {
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
      } else if (stagedDiff.exitCode != 0) {
        throw StateError('Unable to inspect staged RA-25 fixture changes: ${stagedDiff.stderr}');
      }
    }
    gitSha = (await _run('git', ['-C', worktree.path, 'rev-parse', 'HEAD'])).stdout.toString().trim();
  });

  tearDownAll(() async {
    await _run('git', ['worktree', 'remove', '--force', worktree.path]);
  });

  test('versionCode plan upgrades through arm64 to armv7 and back without a time-based number', () async {
    final result = await _runVersioning('''
      \$installed = Get-Ra25InstalledVersionCode 'Unable to find package: com.example.test' 0
      \$arm64First = Get-Ra25VersionCodePlan \$installed 'arm64'
      \$armv7 = Get-Ra25VersionCodePlan \$arm64First.builtVersionCode 'armv7'
      \$arm64Again = Get-Ra25VersionCodePlan \$armv7.builtVersionCode 'arm64'
      @(\$arm64First, \$armv7, \$arm64Again) | ConvertTo-Json -Compress
    ''');
    final plans = (jsonDecode(result) as List<dynamic>).cast<Map<String, dynamic>>();

    expect(plans.map((plan) => plan['installedVersionCode']), [0, 2001, 2002]);
    expect(plans.map((plan) => plan['builtVersionCode']), [2001, 2002, 2003]);
    expect(plans.map((plan) => plan['abi']), ['arm64', 'armv7', 'arm64']);
    expect(plans.map((plan) => plan['buildNumber']), [1, 1002, 3]);
  });

  test('versionCode readers reject unavailable, ambiguous and out-of-range values', () async {
    final valid = await _runVersioning('''
      \$installed = Get-Ra25InstalledVersionCode "versionCode=2147483646 minSdk=26 targetSdk=35" 0
      \$apk = Get-Ra25ApkVersionCode "package: name='com.example.test' versionCode='2147483647' versionName='1.0'"
      [pscustomobject]@{ installed = \$installed; apk = \$apk } | ConvertTo-Json -Compress
    ''');
    expect(jsonDecode(valid), {'installed': 2147483646, 'apk': 2147483647});

    final missing = await _runVersioning("Get-Ra25InstalledVersionCode 'Unable to find package: com.example.test' 0");
    expect(missing, '0');

    final unreadable = await _runVersioning("Get-Ra25InstalledVersionCode '' 1", expectFailure: true);
    expect(unreadable, contains('Unable to read installed package information'));

    final malformed = await _runVersioning("Get-Ra25InstalledVersionCode 'package has no version metadata' 0", expectFailure: true);
    expect(malformed, contains('Unable to determine one installed versionCode'));

    final overflow = await _runVersioning("Get-Ra25VersionCodePlan 2147483647 'arm64'", expectFailure: true);
    expect(overflow, contains("Android's supported range"));
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
    final fakeAdb = await _writeFakeAdb('missing-after-timeout');
    addTearDown(() async {
      await fakeAdb.command.delete();
      await fakeAdb.calls.delete();
    });

    final elapsed = Stopwatch()..start();
    final result = await _validateWithFakeAdb(worktree.path, gitSha, runId, fakeAdb.command, timeoutSeconds: 2);
    elapsed.stop();

    expect(result.exitCode, isNot(0));
    expect(elapsed.elapsed, greaterThanOrEqualTo(const Duration(seconds: 2)));
    final calls = await fakeAdb.calls.readAsLines();
    expect(calls.length, greaterThanOrEqualTo(2));
    expect(calls, everyElement('-s ra25-fake-device logcat -d -v raw'));
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

Future<({File command, File calls})> _writeFakeAdb(String name) async {
  final suffix = '${DateTime.now().microsecondsSinceEpoch}';
  final command = File('${Directory.systemTemp.path}\\yuv-ffi-ra25-$name-$suffix.cmd');
  final calls = File('${Directory.systemTemp.path}\\yuv-ffi-ra25-$name-$suffix.calls');
  await command.writeAsString('@echo off\r\necho %*>>"${calls.path}"\r\necho unrelated logcat output\r\n');
  return (command: command, calls: calls);
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

Future<String> _runVersioning(String expression, {bool expectFailure = false}) async {
  final helper = File('tool/probe/release_android_versioning.ps1').absolute.path.replaceAll("'", "''");
  final result = await Process.run('pwsh', ['-NoProfile', '-Command', ". '$helper'; $expression"]);
  final output = '${result.stdout}\n${result.stderr}'.trim();
  if (expectFailure) {
    expect(result.exitCode, isNot(0), reason: output);
    return output;
  }
  expect(result.exitCode, 0, reason: output);
  return result.stdout.toString().trim();
}

Future<ProcessResult> _validateWithFakeAdb(String worktreePath, String gitSha, String runId, File fakeAdb, {int timeoutSeconds = 300}) =>
    Process.run('pwsh', [
      '-NoProfile',
      '-File',
      '$worktreePath\\tool\\probe\\run_release_android.ps1',
      '-GitSha',
      gitSha,
      '-RunId',
      runId,
      '-TimeoutSeconds',
      '$timeoutSeconds',
      '-ValidateAdbPath',
      fakeAdb.path,
    ], workingDirectory: worktreePath);

Future<ProcessResult> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw StateError('$executable ${arguments.join(' ')} failed:\n${result.stdout}\n${result.stderr}');
  }
  return result;
}
