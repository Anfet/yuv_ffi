import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('example probe helpers and golden match the package sources', () {
    final source = Directory('test/probe');
    final copy = Directory('example/integration_test/helpers/probe');
    final sourceFiles = _files(source);
    final copiedFiles = _files(copy);
    expect(copiedFiles.keys, unorderedEquals(sourceFiles.keys));
    for (final path in sourceFiles.keys) {
      expect(copiedFiles[path], sourceFiles[path], reason: '$path is out of sync');
    }
    expect(File('example/assets/probe/golden.json').readAsBytesSync(), File('test/probe/golden.json').readAsBytesSync());
  });
}

Map<String, List<int>> _files(Directory root) {
  if (!root.existsSync()) return {};
  return {
    for (final entity in root.listSync(recursive: true).whereType<File>())
      entity.path.substring(root.path.length + 1).replaceAll('\\', '/'): entity.readAsBytesSync(),
  };
}
