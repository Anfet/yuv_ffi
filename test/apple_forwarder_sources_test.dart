@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _srcDir = 'src';
const _cmakeListsPath = 'src/CMakeLists.txt';
const _cmakeSourceDirPrefix = r'${CMAKE_CURRENT_SOURCE_DIR}/';
const _forwarderPrefix = '../../src/';

const _forwarderDirs = <String, String>{'iOS': 'ios/Classes', 'macOS': 'macos/Classes'};

/// YUV-06: the Apple pod targets must compile the same translation units the
/// CMake build does.
///
/// CocoaPods compiles `Classes/**/*`, and the podspec cannot reference paths
/// outside the pod directory, so each Apple platform reaches the shared C
/// sources through forwarder files that `#include` them relatively. That
/// indirection is invisible to every other check in this repository:
/// `test/cmake_sources_test.dart` keeps `src/CMakeLists.txt` honest, which
/// covers Linux, Windows and Android, but a source added to CMakeLists.txt and
/// forgotten in `ios/Classes` or `macos/Classes` still builds and still passes
/// CI everywhere except an actual Apple consumer's link step — and even there
/// it only fails when something calls the missing symbol.
///
/// That is exactly how `src/yuv/abi/*.c`, `src/yuv/utils/checked_arithmetic.c`,
/// `src/yuv/utils/validated_view.c` and `src/yuv/bgra8888/bgra8888_block_uv.c`
/// ended up absent from both forwarder sets while every gate stayed green: the
/// versioned ABI symbols are not reachable from Dart yet, so nothing called
/// them. This test makes the omission loud instead of waiting for the call
/// site to arrive.
///
/// Two invariants per platform, both compared by full path relative to `src/`:
///  - every source in the CMake list is included exactly once;
///  - nothing is included that CMake does not build.
///
/// Compiling the same translation unit twice is a duplicate-symbol link error,
/// so "exactly once" is checked across the whole forwarder set, not per file.
void main() {
  // Parsed inside the group's tests rather than at top level: the helpers
  // assert with `expect`, which throws outside a running test.
  late Set<String> cmakeSources;

  group('Apple forwarders stay in sync with src/CMakeLists.txt', () {
    setUp(() {
      cmakeSources = _parseSourcesFromCMakeLists(File(_cmakeListsPath).readAsStringSync()).toSet();
    });

    for (final entry in _forwarderDirs.entries) {
      final platform = entry.key;
      final directory = entry.value;

      test('$platform includes every CMake source exactly once, and nothing else', () {
        final included = _includesFromForwarders(directory);
        final result = _compare(expected: cmakeSources, included: included);

        expect(
          result.duplicates,
          isEmpty,
          reason:
              'a translation unit included by more than one $platform forwarder is a '
              'duplicate-symbol link error in the pod target: ${result.duplicates}',
        );
        expect(
          result.isInSync,
          isTrue,
          reason:
              '$directory does not forward the same sources src/CMakeLists.txt builds.\n'
              'Built by CMake but not forwarded (missing symbols on $platform): ${result.missingFromForwarders}\n'
              'Forwarded but not built by CMake (stale include): ${result.extraInForwarders}',
        );
      });
    }

    test('negative control: dropping one include makes the check fail', () {
      // Proves the comparison is actually load-bearing. Uses a real, currently
      // forwarded entry so the control cannot pass by matching nothing.
      const droppedSource = 'yuv/yuv420/yuv420_crop.c';
      final included = _includesFromForwarders(_forwarderDirs['macOS']!)..removeWhere((path) => path == droppedSource);

      final result = _compare(expected: cmakeSources, included: included);

      expect(
        result.isInSync,
        isFalse,
        reason:
            'the comparison must go RED when a forwarded source disappears; it did not, '
            'so the in-sync tests above would not catch a missing include either',
      );
      expect(result.missingFromForwarders, contains(droppedSource));
    });

    test('negative control: a stale include with no CMake entry makes the check fail', () {
      final included = _includesFromForwarders(_forwarderDirs['macOS']!)..add('yuv/does_not_exist_on_disk.c');

      final result = _compare(expected: cmakeSources, included: included);

      expect(result.isInSync, isFalse, reason: 'the comparison must go RED when a forwarder includes a source CMake does not build; it did not');
      expect(result.extraInForwarders, contains('yuv/does_not_exist_on_disk.c'));
    });

    test('negative control: the same source included twice is reported as a duplicate', () {
      const repeated = 'yuv/yuv.c';
      final included = _includesFromForwarders(_forwarderDirs['macOS']!)..add(repeated);

      final result = _compare(expected: cmakeSources, included: included);

      expect(
        result.duplicates,
        contains(repeated),
        reason: 'the duplicate check must go RED when one translation unit is included twice; it did not',
      );
    });

    test('every forwarded path resolves to a file on disk', () {
      // A typo inside an #include is a compile error only on an Apple host.
      // Resolving the paths here turns it into a failure on every platform.
      for (final entry in _forwarderDirs.entries) {
        for (final source in _includesFromForwarders(entry.value)) {
          expect(File('$_srcDir/$source').existsSync(), isTrue, reason: '${entry.key} forwards "$source", which does not exist under $_srcDir/');
        }
      }
    });
  });
}

/// Result of comparing the CMake source set against the paths a platform's
/// forwarders include, both keyed by full path relative to `src/`.
class _ComparisonResult {
  _ComparisonResult({required this.missingFromForwarders, required this.extraInForwarders, required this.duplicates});

  final Set<String> missingFromForwarders;
  final Set<String> extraInForwarders;
  final Set<String> duplicates;

  bool get isInSync => missingFromForwarders.isEmpty && extraInForwarders.isEmpty;
}

_ComparisonResult _compare({required Set<String> expected, required List<String> included}) {
  final duplicates = <String>{
    for (final path in included.toSet())
      if (included.where((p) => p == path).length > 1) path,
  };
  final includedSet = included.toSet();

  return _ComparisonResult(
    missingFromForwarders: expected.difference(includedSet),
    extraInForwarders: includedSet.difference(expected),
    duplicates: duplicates,
  );
}

/// Every `.c` path included by the forwarders in [directory], as a path
/// relative to `src/`, in encounter order and with repeats preserved so the
/// duplicate check can see them.
List<String> _includesFromForwarders(String directory) {
  final forwarders = Directory(directory).listSync().whereType<File>().where((file) => file.path.endsWith('.c')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  expect(forwarders, isNotEmpty, reason: 'no forwarder .c files found in $directory');

  final includePattern = RegExp(r'^\s*#\s*include\s+"([^"]+\.c)"', multiLine: true);

  return <String>[
    for (final forwarder in forwarders)
      for (final match in includePattern.allMatches(forwarder.readAsStringSync())) _relativeToSrc(forwarder.path, match.group(1)!),
  ];
}

/// Converts a forwarder's `../../src/yuv/...` include target into a path
/// relative to `src/`.
///
/// Rejects a repeated separator rather than normalizing it: `src/yuv//foo.c`
/// compiles, so the double slashes that used to sit in the iOS forwarders were
/// invisible, and normalizing here would let them come back.
String _relativeToSrc(String forwarderPath, String includeTarget) {
  expect(
    includeTarget.startsWith(_forwarderPrefix),
    isTrue,
    reason: '$forwarderPath includes "$includeTarget", which does not start with "$_forwarderPrefix"',
  );
  final relative = includeTarget.substring(_forwarderPrefix.length);
  expect(relative, isNot(contains('//')), reason: '$forwarderPath includes "$includeTarget", which contains a repeated path separator');
  return relative;
}

/// Parses the explicit `set(SOURCES ...)` block in `src/CMakeLists.txt` and
/// returns each entry as a path relative to `src/`.
List<String> _parseSourcesFromCMakeLists(String contents) {
  final setStart = contents.indexOf('set(SOURCES');
  expect(setStart, greaterThanOrEqualTo(0), reason: 'CMakeLists.txt must declare set(SOURCES ...)');
  final setEnd = contents.indexOf(')', setStart);
  expect(setEnd, greaterThan(setStart), reason: 'unterminated set(SOURCES ...) block');
  final block = contents.substring(setStart, setEnd);

  final entries = <String>[for (final match in RegExp(r'"([^"]+\.c)"').allMatches(block)) match.group(1)!.substring(_cmakeSourceDirPrefix.length)];

  expect(entries, isNotEmpty, reason: 'no .c entries parsed out of set(SOURCES ...) — parser or file is broken');
  return entries;
}
