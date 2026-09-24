import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';

/// The eleven ABI v1 processing symbols from
/// `doc/api-abi-0.4-design.md` section 11 / `src/yuv/abi/h/yuv_ops_v1.h`.
///
/// This is the hand-kept reference list the gate judges every source against,
/// including the shared Dart manifest in
/// `lib/src/yuv/shared/yuv_abi_v1_symbols.dart`. It is deliberately NOT that
/// manifest: the Dart manifest is one of the four sources being cross-checked,
/// so a list read from it could not prove it agrees with the other three. For
/// the same reason it is not parsed out of the header, which is the first source
/// checked.
const List<String> _abiV1Symbols = [
  'yuv_convert_v1',
  'yuv_black_white_v1',
  'yuv_grayscale_v1',
  'yuv_negate_v1',
  'yuv_gaussian_blur_v1',
  'yuv_mean_blur_v1',
  'yuv_box_blur_v1',
  'yuv_crop_v1',
  'yuv_flip_v1',
  'yuv_rotate_v1',
  'yuv_chroma_swap_v1',
];

const _headerPath = 'src/yuv/abi/h/yuv_ops_v1.h';
const _ffigenConfigPath = 'ffigen.yaml';
const _wasmBuildScriptPath = 'tool/wasm/build_wasm.sh';
const _dartManifestPath = 'lib/src/yuv/shared/yuv_abi_v1_symbols.dart';
const _nativeRunnerPath = 'lib/src/yuv/impl/io/abi/yuv_abi_v1_runner.dart';
const _webDispatchPath = 'lib/src/yuv/impl/web/yuv_abi_v1_dispatch_web.dart';
const _webBackendPath = 'lib/src/yuv/impl/web/yuv_web.dart';
const _webRunnerPath = 'lib/src/yuv/impl/web/abi/yuv_abi_v1_web_runner.dart';

/// Extracts every `FFI_PLUGIN_EXPORT YuvStatus <name>(` declaration from
/// [_headerPath]: the ground truth for what ABI v1 actually declares.
Set<String> _symbolsDeclaredInHeader() {
  final content = File(_headerPath).readAsStringSync();
  final regex = RegExp(r'FFI_PLUGIN_EXPORT\s+YuvStatus\s+(\w+)\s*\(');
  return regex.allMatches(content).map((m) => m.group(1)!).toSet();
}

/// Extracts every `yuv_*_v1`-shaped name matched by `functions.include` in
/// [_ffigenConfigPath].
///
/// `ffigen.yaml`'s `functions.include` list holds regex patterns, not exact
/// names (`'yuv_.*_v1'`), so this does not try to be a general YAML/regex
/// evaluator. It asserts the one pattern this task added is present and
/// covers every symbol in [_abiV1Symbols] by matching each symbol name
/// against it directly, which is the same thing ffigen itself does when it
/// resolves `include` against the parsed header declarations.
Set<String> _symbolsMatchedByFfigenAllowlist() {
  final content = File(_ffigenConfigPath).readAsStringSync();
  final includePatterns = _yamlListUnder(content, 'functions:', 'include:');
  final matched = <String>{};
  for (final pattern in includePatterns) {
    final regex = RegExp('^$pattern\$');
    for (final symbol in _abiV1Symbols) {
      if (regex.hasMatch(symbol)) {
        matched.add(symbol);
      }
    }
  }
  return matched;
}

/// Extracts every `_yuv_*_v1` entry from `EXPORTED_FUNCTIONS` in
/// [_wasmBuildScriptPath], with the leading Emscripten `_` stripped so it is
/// directly comparable to [_abiV1Symbols].
Set<String> _symbolsExportedByWasmBuildScript() {
  final content = File(_wasmBuildScriptPath).readAsStringSync();
  final line = content.split('\n').firstWhere((l) => l.trimLeft().startsWith('EXPORTED_FUNCTIONS='), orElse: () => '');
  expect(line, isNotEmpty, reason: 'EXPORTED_FUNCTIONS= line not found in $_wasmBuildScriptPath');
  final regex = RegExp(r"'_(yuv_\w+_v1)'");
  return regex.allMatches(line).map((m) => m.group(1)!).toSet();
}

/// Every `yuv_*_v1` string literal declared as a constant in
/// [_dartManifestPath]: the Dart side both backends name their symbols from.
///
/// Read from the file rather than from the imported [yuvAbiV1Symbols] list, so
/// a symbol whose constant exists but was left out of that list -- a partial
/// wiring, exactly what the DoD calls out -- is still seen here and can be
/// compared against the list separately.
Set<String> _symbolsDeclaredInDartManifest() {
  final content = File(_dartManifestPath).readAsStringSync();
  final regex = RegExp(r"^const String \w+ = '(yuv_\w+_v1)';", multiLine: true);
  return regex.allMatches(content).map((m) => m.group(1)!).toSet();
}

/// Returns the scalar list entries directly under `outerKey: -> innerKey:` in
/// a small, YAML subset used by `ffigen.yaml`: two-space-indented top-level
/// keys, four-space-indented nested keys, and `  - 'value'` list items. Good
/// enough for this one file; not a general YAML parser.
List<String> _yamlListUnder(String yaml, String outerKey, String innerKey) {
  final lines = yaml.split('\n');
  int i = 0;
  while (i < lines.length && lines[i].trim() != outerKey) {
    i++;
  }
  expect(i, lessThan(lines.length), reason: 'top-level key "$outerKey" not found in $_ffigenConfigPath');
  i++;
  while (i < lines.length && lines[i].trim() != innerKey) {
    // Stop scanning at the next top-level (non-indented) key, so a search
    // for `functions: -> exclude:` cannot walk into the following top-level
    // section (e.g. `structs:`) and silently return nothing found there
    // instead of failing loudly.
    if (lines[i].isNotEmpty && !lines[i].startsWith(' ')) break;
    i++;
  }
  expect(i, lessThan(lines.length), reason: 'nested key "$innerKey" under "$outerKey" not found in $_ffigenConfigPath');
  i++;
  final values = <String>[];
  final itemPattern = RegExp(r"^\s*-\s*'([^']*)'\s*$");
  while (i < lines.length) {
    final match = itemPattern.firstMatch(lines[i]);
    if (match == null) break;
    values.add(match.group(1)!);
    i++;
  }
  return values;
}

void main() {
  group('ABI v1 symbol manifest', () {
    test('the reference list itself names exactly the eleven section-11 symbols', () {
      expect(_abiV1Symbols.toSet().length, 11, reason: 'reference list has a duplicate entry');
      expect(_abiV1Symbols, everyElement(matches(RegExp(r'^yuv_\w+_v1$'))));
    });

    test('every symbol is declared in src/yuv/abi/h/yuv_ops_v1.h', () {
      final declared = _symbolsDeclaredInHeader();
      expect(declared, containsAll(_abiV1Symbols));
      expect(declared.length, _abiV1Symbols.length, reason: 'header declares a symbol the reference list does not name, or vice versa');
    });

    test('every symbol is matched by the ffigen.yaml functions.include allowlist', () {
      final matched = _symbolsMatchedByFfigenAllowlist();
      expect(matched, containsAll(_abiV1Symbols));
      expect(matched.length, _abiV1Symbols.length);
    });

    test('every symbol is exported by tool/wasm/build_wasm.sh', () {
      final exported = _symbolsExportedByWasmBuildScript();
      expect(exported, containsAll(_abiV1Symbols));
      expect(exported.length, _abiV1Symbols.length, reason: 'the WASM build exports a yuv_*_v1 symbol the reference list does not name');
    });

    test('every symbol is declared by the shared Dart manifest both backends dispatch from', () {
      final declared = _symbolsDeclaredInDartManifest();
      expect(declared, containsAll(_abiV1Symbols));
      expect(declared.length, _abiV1Symbols.length, reason: '$_dartManifestPath declares a symbol the reference list does not name');
    });

    test('the exported Dart symbol list holds every declared constant, so none is half-wired', () {
      // Guards the specific "partial wiring" failure the DoD names: a constant
      // declared in the manifest file but left out of `yuvAbiV1Symbols`, which
      // would make it invisible to every consumer that iterates the list.
      expect(yuvAbiV1Symbols.toSet(), _symbolsDeclaredInDartManifest());
      expect(yuvAbiV1Symbols, hasLength(11));
      expect(yuvAbiV1Symbols.toSet(), hasLength(11), reason: 'yuvAbiV1Symbols has a duplicate entry');
    });

    test('all four sources agree exactly, with no symbol present in only some of them', () {
      // The four-way comparison itself, as sets rather than as four separate
      // containsAll checks: a symbol in the header but not the WASM exports, or
      // in the Dart manifest but not the header, fails here.
      final header = _symbolsDeclaredInHeader();
      final ffigen = _symbolsMatchedByFfigenAllowlist();
      final wasm = _symbolsExportedByWasmBuildScript();
      final dart = _symbolsDeclaredInDartManifest();
      final reference = _abiV1Symbols.toSet();

      expect(header, reference, reason: 'C header disagrees with the reference list');
      expect(ffigen, reference, reason: 'ffigen allowlist disagrees with the reference list');
      expect(wasm, reference, reason: 'WASM EXPORTED_FUNCTIONS disagrees with the reference list');
      expect(dart, reference, reason: 'shared Dart manifest disagrees with the reference list');
    });

    test('the native runner dispatches every symbol through the shared manifest constant', () {
      // Being declared is not being dispatched. The runner must reach each
      // symbol through the manifest constant, not a re-spelled literal, or the
      // manifest would be decorative and the two backends could still drift.
      final content = File(_nativeRunnerPath).readAsStringSync();
      final manifest = File(_dartManifestPath).readAsStringSync();
      for (final symbol in _abiV1Symbols) {
        final constantName = RegExp("const String (\\w+) = '$symbol';").firstMatch(manifest)?.group(1);
        expect(constantName, isNotNull, reason: '$_dartManifestPath declares no constant for $symbol');
        expect(content, contains(constantName!), reason: '$_nativeRunnerPath never dispatches $symbol through $constantName');
        expect(content, contains('ffiBingings.$symbol('), reason: '$_nativeRunnerPath never calls the generated binding for $symbol');
      }
      expect(
        content,
        contains("import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';"),
        reason: '$_nativeRunnerPath must take its symbol names from the shared manifest',
      );
    });

    test('the Web runner dispatches every symbol through the shared manifest constant', () {
      // The Web mirror of the native-runner check above, and the half of the
      // gate YUV-51 made real: before it, the Web side could only be asked
      // whether it *named* the symbols. Now the Web runner must reach each one
      // through the manifest constant, exactly as the native runner does, so a
      // symbol wired on one backend but not the other fails here.
      final content = File(_webRunnerPath).readAsStringSync();
      final manifest = File(_dartManifestPath).readAsStringSync();
      for (final symbol in _abiV1Symbols) {
        final constantName = RegExp("const String (\\w+) = '$symbol';").firstMatch(manifest)?.group(1);
        expect(constantName, isNotNull, reason: '$_dartManifestPath declares no constant for $symbol');
        expect(content, contains(constantName!), reason: '$_webRunnerPath never dispatches $symbol through $constantName');
        expect(
          content,
          isNot(contains("'$symbol'")),
          reason: '$_webRunnerPath re-spells $symbol as a literal instead of taking it from the shared manifest',
        );
      }
      expect(
        content,
        contains("import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';"),
        reason: '$_webRunnerPath must take its symbol names from the shared manifest',
      );
    });

    test('the Web backend runs its public operations through the ABI v1 Web runner', () {
      // The Web equivalent of "never calls the generated binding by hand": the
      // backend must go through the runner, and must not have kept a legacy
      // per-format entry point behind it.
      final backend = File(_webBackendPath).readAsStringSync();
      expect(backend, contains('YuvAbiV1WebRunner.'), reason: '$_webBackendPath must dispatch through the ABI v1 Web runner');
      for (final legacy in ['yuv420_', 'nv21_', 'bgra8888_', 'nvXX_to_nvYY']) {
        expect(backend, isNot(contains("'$legacy")), reason: '$_webBackendPath still calls the legacy processing symbol prefix $legacy');
      }
    });

    test('the Web dispatch resolves its symbols from the shared manifest and is reached from the Web backend', () {
      // The fourth side of the gate, as actual Web dispatch rather than only a
      // build-script export list: the Web dispatch layer must iterate the shared
      // manifest (never its own copy of the names), and the Web backend must
      // reference that layer, so the list is wired into real dispatch rather
      // than sitting unused.
      final dispatch = File(_webDispatchPath).readAsStringSync();
      expect(
        dispatch,
        contains("import 'package:yuv_ffi/src/yuv/shared/yuv_abi_v1_symbols.dart';"),
        reason: '$_webDispatchPath must take its symbol names from the shared manifest',
      );
      expect(dispatch, contains('yuvAbiV1Symbols'), reason: '$_webDispatchPath must iterate the shared manifest list');
      for (final symbol in _abiV1Symbols) {
        expect(
          dispatch,
          isNot(contains("'$symbol'")),
          reason: '$_webDispatchPath re-spells $symbol as a literal instead of taking it from the shared manifest',
        );
      }

      final backend = File(_webBackendPath).readAsStringSync();
      final runner = File(_webRunnerPath).readAsStringSync();
      expect(backend, contains("import 'yuv_abi_v1_dispatch_web.dart';"), reason: '$_webBackendPath must import the ABI v1 Web dispatch');
      expect(backend, contains('YuvAbiV1WebDispatch.'), reason: '$_webBackendPath must actually use the ABI v1 Web dispatch');
      // Since YUV-51 the per-operation dispatch happens in the runner, so the
      // dispatch layer has to be reached from there too -- otherwise the
      // completeness check could be bypassed by every real operation.
      expect(runner, contains('YuvAbiV1WebDispatch.call('), reason: '$_webRunnerPath must invoke symbols through the ABI v1 Web dispatch');
    });

    test('a symbol missing from any one source is caught, not silently tolerated', () {
      // Negative control for all four positive checks: each source's extracted
      // set is corrupted in memory, one symbol at a time, and the same
      // comparison the gate uses must reject it. Corrupting the in-memory copy
      // rather than the file on disk keeps this from needing cleanup on a
      // failing assertion.
      final reference = _abiV1Symbols.toSet();
      final sources = <String, Set<String>>{
        'header': _symbolsDeclaredInHeader(),
        'ffigen': _symbolsMatchedByFfigenAllowlist(),
        'wasm': _symbolsExportedByWasmBuildScript(),
        'dart manifest': _symbolsDeclaredInDartManifest(),
      };
      for (final entry in sources.entries) {
        for (final symbol in _abiV1Symbols) {
          final broken = entry.value.toSet()..remove(symbol);
          expect(() => expect(broken, reference), throwsA(isA<TestFailure>()), reason: 'dropping $symbol from the ${entry.key} source was tolerated');
        }
      }
    });

    test('a symbol added to only one source is caught as well', () {
      // The opposite drift: a twelfth symbol appearing in one source only. Set
      // equality rejects it; a containsAll-only gate would not.
      final reference = _abiV1Symbols.toSet();
      for (final source in <Set<String>>[
        _symbolsDeclaredInHeader(),
        _symbolsMatchedByFfigenAllowlist(),
        _symbolsExportedByWasmBuildScript(),
        _symbolsDeclaredInDartManifest(),
      ]) {
        final broken = source.toSet()..add('yuv_not_a_real_operation_v1');
        expect(() => expect(broken, reference), throwsA(isA<TestFailure>()));
      }
    });
  });
}
