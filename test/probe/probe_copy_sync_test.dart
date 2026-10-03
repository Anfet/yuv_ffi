@Tags(['probe'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('example probe helpers and golden match the package sources', () {
    final source = Directory('test/probe');
    final copy = Directory('example/integration_test/helpers/probe');
    final sourceFiles = _files(source)..removeWhere((path, _) => rootOnlyFiles.contains(path));
    final copiedFiles = _files(copy)..removeWhere((path, _) => rootOnlyFiles.contains(path));
    expect(copiedFiles.keys, unorderedEquals(sourceFiles.keys));
    for (final path in sourceFiles.keys) {
      expect(copiedFiles[path], sourceFiles[path], reason: '$path is out of sync');
    }
    expect(File('example/assets/probe/golden.json').readAsBytesSync(), File('test/probe/golden.json').readAsBytesSync());
  });
}

// These helpers run from the package root and have no copy in the example.
const rootOnlyFiles = {
  'android_release_benchmark_contract_test.dart',
  'baseline/windows-13th-gen-intel-r-core-tm-i9-13980hx-x64-release.json',
  'operation_coverage_test.dart',
  'probe_copy_sync_test.dart',
  'probe_performance_test.dart',
  'probe_runner.dart',
  'probe_runner_test.dart',
  'probe_scenarios.dart',
  'release_probe_core_test.dart',
  'run_release_android_test.dart',
  'windows_release_package_provenance_contract_test.dart',
};

Map<String, List<int>> _files(Directory root) {
  if (!root.existsSync()) return {};
  return {
    for (final entity in root.listSync(recursive: true).whereType<File>())
      entity.path.substring(root.path.length + 1).replaceAll('\\', '/'): entity.readAsBytesSync(),
  };
}
