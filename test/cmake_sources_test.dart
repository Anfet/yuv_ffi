@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _srcDir = 'src';
const _cmakeListsPath = 'src/CMakeLists.txt';
const _cmakeSourceDirPrefix = r'${CMAKE_CURRENT_SOURCE_DIR}/';

/// YUV-24: `src/CMakeLists.txt` lists its `.c` sources explicitly instead of
/// using `file(GLOB_RECURSE ... CONFIGURE_DEPENDS ...)`.
///
/// CONFIGURE_DEPENDS requires CMake 3.12; this project intentionally keeps
/// `cmake_minimum_required(VERSION 3.10)` for Android tooling that may
/// resolve an unpinned CMake 3.10.2, and a glob without CONFIGURE_DEPENDS
/// would silently miss newly added sources until the cache is cleared. The
/// explicit list trades that silent failure mode for a loud one: forgetting
/// to add a new file to the list, or leaving a stale/duplicate entry in it,
/// must fail a test — not a build that quietly links the wrong set of
/// object files.
///
/// This test enumerates `.c` files on disk under `src/` and parses the
/// source list out of `CMakeLists.txt`, then compares the two sets by FULL
/// PATH RELATIVE TO `src/` (normalized to forward slashes), not by basename.
///
/// Comparing by basename alone would be unsound: two different directories
/// can contain a file with the same basename (e.g. `yuv/a/foo.c` and
/// `yuv/b/foo.c`). Under a basename comparison both disk paths collapse to
/// the single element `foo.c`, so if CMakeLists.txt lists only one of them,
/// the sets would still compare equal and the test would pass even though
/// the build silently omits a translation unit. Comparing full relative
/// paths closes that hole.
///
/// All four failure modes are exercised as negative controls that run the
/// SAME comparison helper the main test uses, asserting it goes red. None of
/// them writes anything into the production `src/` tree: the first three
/// build a modified in-memory copy of the CMakeLists.txt TEXT (the file on
/// disk is never opened for writing), and the collision control materializes
/// a throwaway fixture tree under `Directory.systemTemp`. Writing probe `.c`
/// files into `src/` would be unsafe even under `try`/`finally` — a killed
/// process leaves them behind, and a concurrent CMake configure or IDE
/// watcher can observe temporary C sources in the real source tree.
///
/// The four modes:
///  - a .c file on disk missing from CMakeLists.txt;
///  - an entry in CMakeLists.txt that does not exist on disk;
///  - the same relative path listed twice (duplicate);
///  - two different files sharing a basename where only one is listed.
void main() {
  group('CMakeLists.txt source list stays in sync with src/**/*.c', () {
    test('every .c file on disk is listed exactly once, and nothing else is listed', () {
      final result = _compare(onDisk: _cSourcesOnDisk(), listed: _parseSourcesFromCMakeLists(File(_cmakeListsPath).readAsStringSync()));

      expect(result.duplicates, isEmpty, reason: 'duplicate source entries in CMakeLists.txt (relative to src/): ${result.duplicates}');
      expect(
        result.isInSync,
        isTrue,
        reason:
            'CMakeLists.txt source list is out of sync with src/**/*.c.\n'
            'Missing from CMakeLists.txt (present on disk): ${result.missingFromCMake}\n'
            'Listed in CMakeLists.txt but not on disk: ${result.extraInCMake}',
      );
    });

    test('negative control: a .c file missing from the list makes the check fail', () {
      final original = File(_cmakeListsPath).readAsStringSync();

      // Remove one real, currently-listed entry to simulate "a new .c file
      // was added on disk but nobody updated CMakeLists.txt".
      const droppedEntry = '"\${CMAKE_CURRENT_SOURCE_DIR}/yuv/abi/yuv_crop_v1.c"';
      expect(original.contains(droppedEntry), isTrue, reason: 'test setup assumption broken: expected entry not found in CMakeLists.txt');
      final broken = original.replaceFirst(RegExp('${RegExp.escape(droppedEntry)}\r?\n'), '');
      expect(broken, isNot(equals(original)), reason: 'test setup did not actually remove anything');

      final result = _compare(onDisk: _cSourcesOnDisk(), listed: _parseSourcesFromCMakeLists(broken));

      expect(
        result.isInSync,
        isFalse,
        reason:
            'the comparison must go RED when a real source is missing from the list; '
            'it did not, which means the completeness test above would not catch this either. '
            'missingFromCMake=${result.missingFromCMake} extraInCMake=${result.extraInCMake}',
      );
      expect(result.missingFromCMake, contains('yuv/abi/yuv_crop_v1.c'));
    });

    test('negative control: an entry with no file on disk makes the check fail', () {
      final original = File(_cmakeListsPath).readAsStringSync();

      const anchorEntry = '"\${CMAKE_CURRENT_SOURCE_DIR}/yuv_ffi.c"';
      expect(original.contains(anchorEntry), isTrue, reason: 'test setup assumption broken: expected entry not found in CMakeLists.txt');
      const phantomEntry = '"\${CMAKE_CURRENT_SOURCE_DIR}/yuv/does_not_exist_on_disk.c"';
      final broken = original.replaceFirst(anchorEntry, '$anchorEntry\n    $phantomEntry');
      expect(broken, isNot(equals(original)), reason: 'test setup did not actually add anything');

      final result = _compare(onDisk: _cSourcesOnDisk(), listed: _parseSourcesFromCMakeLists(broken));

      expect(
        result.isInSync,
        isFalse,
        reason:
            'the comparison must go RED when CMakeLists.txt lists a file absent from disk; '
            'it did not, which means the completeness test above would not catch this either. '
            'missingFromCMake=${result.missingFromCMake} extraInCMake=${result.extraInCMake}',
      );
      expect(result.extraInCMake, contains('yuv/does_not_exist_on_disk.c'));
    });

    test('negative control: a duplicate entry in the list makes the check fail', () {
      final original = File(_cmakeListsPath).readAsStringSync();

      const targetEntry = '"\${CMAKE_CURRENT_SOURCE_DIR}/yuv_ffi.c"';
      expect(original.contains(targetEntry), isTrue, reason: 'test setup assumption broken: expected entry not found in CMakeLists.txt');
      final broken = original.replaceFirst(targetEntry, '$targetEntry\n    $targetEntry');

      final result = _compare(onDisk: _cSourcesOnDisk(), listed: _parseSourcesFromCMakeLists(broken));

      expect(
        result.duplicates,
        isNot(isEmpty),
        reason:
            'the duplicate check must go RED when an entry is listed twice; '
            'it did not, which means the completeness test above would not catch this either',
      );
      expect(result.duplicates, contains('yuv_ffi.c'));
    });

    test('negative control: two files sharing a basename in different directories, '
        'with only one listed, makes the check fail', () {
      // This is the case a basename-only comparison cannot catch: two real
      // files on disk, in different directories, with the identical
      // basename, where the source list names only one of the two full
      // paths. A basename-based comparison would see the name once on disk
      // (as a set element) and once in the list and call it a match,
      // silently dropping the second translation unit from the build. The
      // full-relative-path comparison must not make that mistake.
      //
      // The two probe files are materialized in a THROWAWAY FIXTURE TREE
      // under Directory.systemTemp, never inside the production `src/`
      // tree. Writing probe .c files into `src/` — even with a finally
      // block — is unsafe: killing the test process leaves them behind, and
      // a concurrent CMake configure or IDE file watcher can pick up
      // temporary C sources from the real tree. The temp directory costs
      // nothing and cannot contaminate a build.
      //
      // This is still a REAL disk enumeration, not an in-memory fake: the
      // same `_cSourcesOnDisk` walker the main test uses runs against the
      // fixture root, and the same `_compare` helper judges the result. Only
      // the root directory differs.
      final fixtureRoot = Directory.systemTemp.createTempSync('yuv24_collision_');
      try {
        const basename = 'collision_probe.c';
        const relativeA = 'yuv/dir_a/$basename';
        const relativeB = 'yuv/dir_b/$basename';

        for (final relative in [relativeA, relativeB]) {
          final file = File('${fixtureRoot.path}/$relative');
          file.parent.createSync(recursive: true);
          file.writeAsStringSync('// YUV-24 collision fixture: $relative\n');
        }

        // A synthetic source list that names only relativeA, in exactly the
        // quoted `${CMAKE_CURRENT_SOURCE_DIR}/...` form the real file uses,
        // so the real parser is exercised rather than bypassed.
        final syntheticCMake =
            'set(SOURCES\n'
            '    "$_cmakeSourceDirPrefix$relativeA"\n'
            ')\n';

        final onDisk = _cSourcesOnDisk(root: fixtureRoot.path);
        expect(
          onDisk,
          containsAll(<String>[relativeA, relativeB]),
          reason:
              'test setup assumption broken: both collision probe files should be '
              'enumerated in the fixture tree; got $onDisk',
        );

        final result = _compare(onDisk: onDisk, listed: _parseSourcesFromCMakeLists(syntheticCMake));

        expect(
          result.isInSync,
          isFalse,
          reason:
              'the comparison must go RED when two files share a basename in different '
              'directories and only one is listed; it did not, which means a basename-only '
              'comparison (or a regression back to one) would silently drop a translation '
              'unit from the build. missingFromCMake=${result.missingFromCMake} '
              'extraInCMake=${result.extraInCMake}',
        );
        expect(result.missingFromCMake, contains(relativeB));
        expect(
          result.missingFromCMake,
          isNot(contains(relativeA)),
          reason:
              'the listed path must be recognised as present; if both paths are reported '
              'missing the parser is not matching the entry at all and the redness above '
              'would be vacuous',
        );
      } finally {
        fixtureRoot.deleteSync(recursive: true);
      }

      // The production tree must be exactly as it was: this test never
      // created anything under src/.
      expect(
        Directory('$_srcDir/yuv').listSync().whereType<Directory>().map((d) => d.uri.pathSegments.last),
        isNot(anyElement(startsWith('_'))),
        reason: 'no scratch directory may be left behind under src/yuv',
      );
    });
  });
}

/// Result of comparing the on-disk `.c` file set against the parsed
/// `CMakeLists.txt` entries, both keyed by full path relative to `src/`
/// with forward slashes.
class _ComparisonResult {
  _ComparisonResult({required this.missingFromCMake, required this.extraInCMake, required this.duplicates});

  final Set<String> missingFromCMake;
  final Set<String> extraInCMake;
  final Set<String> duplicates;

  bool get isInSync => missingFromCMake.isEmpty && extraInCMake.isEmpty;
}

_ComparisonResult _compare({required Set<String> onDisk, required List<String> listed}) {
  final duplicates = <String>{
    for (final path in listed.toSet())
      if (listed.where((p) => p == path).length > 1) path,
  };
  final listedSet = listed.toSet();

  return _ComparisonResult(missingFromCMake: onDisk.difference(listedSet), extraInCMake: listedSet.difference(onDisk), duplicates: duplicates);
}

/// Full paths (relative to [root], forward-slash separated, e.g.
/// `yuv/abi/yuv_crop_v1.c`) of every `.c` file found recursively under [root].
///
/// [root] defaults to the production `src/` tree, which is what the main
/// test enumerates. The collision negative control passes a throwaway
/// fixture root instead, so it exercises this exact walker without writing
/// anything into `src/`.
Set<String> _cSourcesOnDisk({String root = _srcDir}) {
  return Directory(
    root,
  ).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.c')).map((file) => _relativeTo(root, file.path)).toSet();
}

/// Normalizes a file path (which may use backslashes on Windows) to a
/// forward-slash path relative to [root], e.g.
/// `src\yuv\abi\yuv_crop_v1.c` -> `yuv/abi/yuv_crop_v1.c`.
String _relativeTo(String root, String filePath) {
  final normalizedRoot = root.replaceAll(r'\', '/');
  final normalized = filePath.replaceAll(r'\', '/');
  final prefix = '$normalizedRoot/';
  expect(normalized.startsWith(prefix), isTrue, reason: 'path "$filePath" is not under the expected root "$root"');
  return normalized.substring(prefix.length);
}

/// Parses the explicit `set(SOURCES ...)` block in `CMakeLists.txt` and
/// returns each entry as a path relative to `src/` (forward-slash
/// separated), with the `${CMAKE_CURRENT_SOURCE_DIR}/` prefix stripped.
///
/// Deliberately string-based rather than a full CMake parser: the list is
/// hand-written, quoted, one entry per line, so this only needs to recognise
/// quoted strings ending in `.c` between `set(SOURCES` and the matching `)`.
List<String> _parseSourcesFromCMakeLists(String contents) {
  final setStart = contents.indexOf('set(SOURCES');
  expect(setStart, greaterThanOrEqualTo(0), reason: 'CMakeLists.txt must declare set(SOURCES ...)');
  final setEnd = contents.indexOf(')', setStart);
  expect(setEnd, greaterThan(setStart), reason: 'unterminated set(SOURCES ...) block');
  final block = contents.substring(setStart, setEnd);

  final entryPattern = RegExp(r'"([^"]+\.c)"');
  final matches = entryPattern.allMatches(block);

  final entries = <String>[];
  for (final match in matches) {
    final rawPath = match.group(1)!;
    expect(
      rawPath.startsWith(_cmakeSourceDirPrefix),
      isTrue,
      reason:
          'CMakeLists.txt entry "$rawPath" does not start with the expected '
          '"$_cmakeSourceDirPrefix" prefix',
    );
    entries.add(rawPath.substring(_cmakeSourceDirPrefix.length));
  }

  expect(entries, isNotEmpty, reason: 'no .c entries parsed out of set(SOURCES ...) — parser or file is broken');
  return entries;
}
