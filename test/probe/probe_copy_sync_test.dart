import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('example probe helpers and golden match the package sources', () {
    final source = Directory('test/probe');
    final copy = Directory('example/integration_test/helpers/probe');
    final sourceFiles = _files(source)..removeWhere((path, _) => _rootOnlyProbeFiles.contains(path));
    final copiedFiles = _files(copy)..removeWhere((path, _) => _rootOnlyProbeFiles.contains(path));
    expect(copiedFiles.keys, unorderedEquals(sourceFiles.keys));
    for (final path in sourceFiles.keys) {
      expect(copiedFiles[path], sourceFiles[path], reason: '$path is out of sync');
    }
    expect(File('example/assets/probe/golden.json').readAsBytesSync(), File('test/probe/golden.json').readAsBytesSync());
  });
}

// The timing executor runs from the package root and will later be imported by
// the platform entrypoints. It has no place in the example's copied correctness
// helpers, which must stay asset-bundle friendly for Web.
const _rootOnlyProbeFiles = {
  'operation_coverage_test.dart',
  'probe_copy_sync_test.dart',
  'probe_performance_test.dart',
  'probe_runner.dart',
  'probe_runner_test.dart',
  'probe_scenarios.dart',
  'release_probe_core_test.dart',
};

Map<String, List<int>> _files(Directory root) {
  if (!root.existsSync()) return {};
  return {
    for (final entity in root.listSync(recursive: true).whereType<File>())
      entity.path.substring(root.path.length + 1).replaceAll('\\', '/'): entity.readAsBytesSync(),
  };
}
