@Tags(['contract'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _smokeFiles = {
  'native_packaging_smoke_test.dart',
  'loader_io_test.dart',
  'cmake_sources_test.dart',
  'apple_forwarder_sources_test.dart',
  'abi_symbol_manifest_test.dart',
};

const _releaseFiles = {
  'release_probe_core_test.dart',
  'windows_release_package_provenance_contract_test.dart',
};

const _tags = {'smoke', 'contract', 'probe', 'reference', 'release'};

String _expectedTag(String path) {
  final name = path.split('/').last;
  if (_smokeFiles.contains(name)) return 'smoke';
  if (path.startsWith('test/reference_')) return 'reference';
  if (path.startsWith('test/probe/') &&
      (name.startsWith('run_') || _releaseFiles.contains(name))) {
    return 'release';
  }
  if (path.startsWith('test/probe/')) return 'probe';
  return 'contract';
}

void main() {
  test('every test file has one primary tag matching its test group', () {
    final files = Directory('test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('_test.dart'));
    final issues = <String>[];
    final tagPattern = RegExp(
      r"^@Tags\s*\(\s*\[([^\]]*)\]\s*\)",
      multiLine: true,
    );
    final valuePattern = RegExp(r"'([^']+)'");

    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      final matches = tagPattern.allMatches(file.readAsStringSync()).toList();
      if (matches.length != 1) {
        issues.add('$path: expected exactly one @Tags annotation');
        continue;
      }

      final values = valuePattern
          .allMatches(matches.single.group(1)!)
          .map((match) => match.group(1)!)
          .toList();
      if (values.length != 1 || !_tags.contains(values.single)) {
        issues.add('$path: expected exactly one recognized primary tag');
        continue;
      }

      final expected = _expectedTag(path);
      if (values.single != expected) {
        issues.add('$path: expected $expected, got ${values.single}');
      }
    }

    expect(issues, isEmpty, reason: issues.join('\n'));
  });
}
