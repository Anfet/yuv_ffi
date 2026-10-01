@Tags(['smoke'])
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _srcDir = 'src';
const _cmakeListsPath = 'src/CMakeLists.txt';
const _cmakeSourceDirPrefix = r'${CMAKE_CURRENT_SOURCE_DIR}/';
const _forwarderPrefix = '../../../../src/';
const _forwarderDir = 'darwin/yuv_ffi/Sources/yuv_ffi';

/// The Apple build must compile the same translation units that CMake does.
///
/// iOS and macOS share one directory, `darwin/yuv_ffi/Sources/yuv_ffi`, which
/// is both the CocoaPods source root (`s.source_files`) and the Swift Package
/// Manager target. Neither can reference paths outside its package, so each
/// source listed in `src/CMakeLists.txt` is reached through a forwarder `.c`
/// file, named after the source, that `#include`s it relatively. That
/// indirection is invisible to every other check in this repository:
/// `test/cmake_sources_test.dart` keeps `src/CMakeLists.txt` honest, which
/// covers Linux, Windows and Android, but a source added to CMakeLists.txt and
/// forgotten in the forwarder directory still builds and still passes CI
/// everywhere except an actual Apple consumer's link step, and even there it
/// only fails when something calls the missing symbol.
///
/// That is exactly how `src/yuv/abi/*.c`, `src/yuv/utils/checked_arithmetic.c`
/// and `src/yuv/utils/validated_view.c` once ended up absent from the forwarder
/// sets while every gate stayed green: back then nothing called the versioned
/// ABI symbols, so the missing link step had nothing to fail on. They are the
/// whole library because the legacy sources have been removed, which makes this
/// check the only thing standing between a forgotten include and a target that
/// links without the operation a caller asks for.
///
/// Invariants, compared by full path relative to `src/`:
///  - every source in the CMake list is included exactly once;
///  - nothing is included that CMake does not build;
///  - every forwarder contains exactly one `#include` of a `.c` file;
///  - every forwarder is named after the basename of the source it includes.
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

    test('forwarders include every CMake source exactly once, and nothing else', () {
      final included = _includesFromForwarders();
      final result = _compare(expected: cmakeSources, included: included);

      expect(
        result.duplicates,
        isEmpty,
        reason:
            'a translation unit included by more than one forwarder is a '
            'duplicate-symbol link error in the Apple target: ${result.duplicates}',
      );
      expect(
        result.isInSync,
        isTrue,
        reason:
            '$_forwarderDir does not forward the same sources src/CMakeLists.txt builds.\n'
            'Built by CMake but not forwarded (missing symbols on Apple): ${result.missingFromForwarders}\n'
            'Forwarded but not built by CMake (stale include): ${result.extraInForwarders}',
      );
    });

    test('every forwarder holds exactly one .c include and is named after its source', () {
      for (final forwarder in _forwarderFiles()) {
        final targets = _includeTargets(forwarder);
        expect(targets, hasLength(1), reason: '${forwarder.path} must contain exactly one #include of a .c file, found $targets');
        expect(
          _basename(forwarder.path),
          _basename(targets.single),
          reason: '${forwarder.path} includes "${targets.single}"; a forwarder must be named after the source it includes',
        );
      }
    });

    test('negative control: a forwarder with two includes is counted as two', () {
      final targets = _includeTargetsOf('#include "../../../../src/yuv/abi/a.c"\n#include "../../../../src/yuv/abi/b.c"\n');

      expect(targets, hasLength(2), reason: 'the extraction must see both includes, or the one-include invariant could never go RED');
    });

    test('negative control: a forwarder named differently from its source is detected', () {
      final targets = _includeTargetsOf('#include "../../../../src/yuv/abi/yuv_crop_v1.c"\n');

      expect(_basename(targets.single), isNot('yuv_flip_v1.c'), reason: 'the basename comparison must go RED for a misnamed forwarder');
    });

    test('negative control: dropping one include makes the check fail', () {
      // Proves the comparison is actually load-bearing. Uses a real, currently
      // forwarded entry so the control cannot pass by matching nothing.
      const droppedSource = 'yuv/abi/yuv_crop_v1.c';
      final included = _includesFromForwarders()..removeWhere((path) => path == droppedSource);

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
      final included = _includesFromForwarders()..add('yuv/does_not_exist_on_disk.c');

      final result = _compare(expected: cmakeSources, included: included);

      expect(result.isInSync, isFalse, reason: 'the comparison must go RED when a forwarder includes a source CMake does not build; it did not');
      expect(result.extraInForwarders, contains('yuv/does_not_exist_on_disk.c'));
    });

    test('negative control: the same source included twice is reported as a duplicate', () {
      const repeated = 'yuv/abi/yuv_crop_v1.c';
      final included = _includesFromForwarders()..add(repeated);

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
      for (final source in _includesFromForwarders()) {
        expect(File('$_srcDir/$source').existsSync(), isTrue, reason: 'a forwarder includes "$source", which does not exist under $_srcDir/');
      }
    });
  });
}

/// Result of comparing the CMake source set against the paths the forwarders
/// include, both keyed by full path relative to `src/`.
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

String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

/// The forwarder `.c` files in [_forwarderDir], sorted by path.
List<File> _forwarderFiles() {
  final forwarders = Directory(_forwarderDir).listSync().whereType<File>().where((file) => file.path.endsWith('.c')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  expect(forwarders, isNotEmpty, reason: 'no forwarder .c files found in $_forwarderDir');
  return forwarders;
}

/// Every `.c` include target in [text], in encounter order.
List<String> _includeTargetsOf(String text) => <String>[
  for (final match in RegExp(r'^\s*#\s*include\s+"([^"]+\.c)"', multiLine: true).allMatches(text)) match.group(1)!,
];

List<String> _includeTargets(File forwarder) => _includeTargetsOf(forwarder.readAsStringSync());

/// Every `.c` path included by the forwarders, as a path relative to `src/`,
/// in encounter order and with repeats preserved so the duplicate check can
/// see them.
List<String> _includesFromForwarders() => <String>[
  for (final forwarder in _forwarderFiles())
    for (final target in _includeTargets(forwarder)) _relativeToSrc(forwarder.path, target),
];

/// Converts a forwarder's `../../../../src/yuv/...` include target into a path
/// relative to `src/`.
///
/// Rejects a repeated separator rather than normalizing it: `src/yuv//foo.c`
/// compiles despite the doubled separator, and normalizing here would let that
/// invalid path pass again.
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
