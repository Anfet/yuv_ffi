import 'dart:convert';
import 'dart:io';

class _SuiteResult {
  _SuiteResult(this.path);

  final String path;
  final Map<int, String> names = {};
  final Set<int> skipped = {};
  final Set<int> finished = {};
  final Set<int> failed = {};
  final Map<int, List<String>> errors = {};
  final Map<int, List<String>> stacks = {};
  final Map<int, List<String>> prints = {};
}

Future<void> main() async {
  final suites = <int, _SuiteResult>{};
  final tests = <int, _SuiteResult>{};
  var passed = 0;
  var skipped = 0;
  var failed = 0;
  var sawTest = false;
  var doneSuccessfully = false;
  var elapsedMilliseconds = 0;

  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final Map<String, dynamic> event;
    try {
      event = jsonDecode(line) as Map<String, dynamic>;
    } on FormatException catch (error) {
      stderr.writeln('Invalid flutter test JSON: ${error.message}');
      exitCode = 1;
      return;
    }

    switch (event['type']) {
      case 'suite':
        final suite = event['suite'] as Map<String, dynamic>;
        final id = suite['id'] as int;
        suites[id] = _SuiteResult((suite['path'] as String?) ?? '<unknown test file>');
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>;
        final id = test['id'] as int;
        final suite = suites[test['suiteID'] as int];
        if (suite != null) {
          suite.names[id] = test['name'] as String;
          tests[id] = suite;
          if (!(test['name'] as String).startsWith('loading ')) sawTest = true;
        }
      case 'testDone':
        final id = event['testID'] as int;
        final suite = tests[id];
        if (suite == null) break;
        final name = suite.names[id] ?? '<unknown test>';
        final isLoad = name.startsWith('loading ');
        final result = event['result'] as String?;
        if (event['skipped'] == true) {
          if (!isLoad) {
            suite.skipped.add(id);
            skipped++;
          }
        } else if (result == 'success') {
          if (!isLoad) {
            suite.finished.add(id);
            passed++;
          }
        } else {
          suite.failed.add(id);
          if (!isLoad) failed++;
        }
      case 'error':
        final id = event['testID'] as int?;
        final suite = id == null ? null : tests[id];
        if (suite != null && event['isFailure'] == true) {
          suite.errors.putIfAbsent(id!, () => []).add((event['error'] as String?) ?? 'Test failed');
          final frames = (event['stackTrace'] as String? ?? '')
              .split('\n')
              .where((frame) => frame.contains('test/') || frame.contains('lib/'))
              .take(5)
              .toList();
          if (frames.isNotEmpty) suite.stacks.putIfAbsent(id, () => []).addAll(frames);
        } else if (suite != null && (suite.names[id!] ?? '').startsWith('loading ')) {
          suite.failed.add(id);
          suite.errors.putIfAbsent(id, () => []).add((event['error'] as String?) ?? 'Test file failed to load');
        }
      case 'print':
        final id = event['testID'] as int?;
        final suite = id == null ? null : tests[id];
        if (suite != null) {
          suite.prints.putIfAbsent(id!, () => []).add((event['message'] as String?) ?? '');
        }
      case 'done':
        doneSuccessfully = event['success'] == true;
        elapsedMilliseconds = event['time'] as int? ?? 0;
    }
  }

  final hasFailedSuite = suites.values.any((suite) => suite.failed.isNotEmpty);
  final showPassedSuites = doneSuccessfully && sawTest && failed == 0 && !hasFailedSuite;
  for (final suite in suites.values) {
    final suiteFailures = suite.failed.toList();
    if (suiteFailures.isNotEmpty) {
      failed += suiteFailures.where((id) => suite.names[id]?.startsWith('loading ') == true).length;
      for (final id in suiteFailures) {
        final name = suite.names[id] ?? '<unknown test>';
        final displayName = name.startsWith('loading ') ? suite.path : name;
        stdout.writeln('${suite.path}  FAILED  $displayName');
        for (final error in suite.errors[id] ?? const <String>[]) {
          stdout.writeln(error);
        }
        for (final frame in suite.stacks[id] ?? const <String>[]) {
          stdout.writeln(frame);
        }
        for (final message in suite.prints[id] ?? const <String>[]) {
          stdout.writeln(message);
        }
      }
    } else if (showPassedSuites) {
      stdout.writeln('${suite.path}  Passed  ${suite.finished.length}');
    }
  }

  final testCount = passed + skipped + failed;
  final ok = doneSuccessfully && sawTest && testCount > 0 && failed == 0;
  stdout.writeln('$passed/${passed + failed} passed, $skipped skipped, $failed failed');
  stdout.writeln('Total: ${(elapsedMilliseconds / 1000).toStringAsFixed(2)} s');
  exitCode = ok ? 0 : 1;
}
