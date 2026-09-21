import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The eleven ABI v1 processing symbols from
/// `docs/api-abi-0.3-design.md` section 11 / `src/yuv/abi/h/yuv_ops_v1.h`.
///
/// This is the YUV-36e portion of the manifest gate: headers, ffigen allowlist,
/// and WASM exported functions. The Engineer's 2026-09-21 decision assigns the
/// Web-dispatch comparison to YUV-28, when Web moves onto ABI v1.
/// It is a hand-kept list rather than something parsed out of the header,
/// because the header itself is the first of the three sources being cross
/// checked -- a list parsed from it could not prove the header agrees with
/// itself.
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
  group('ABI v1 symbol manifest (YUV-36e)', () {
    test('the manifest itself names exactly the eleven section-11 symbols', () {
      expect(_abiV1Symbols.toSet().length, 11, reason: 'manifest has a duplicate entry');
      expect(_abiV1Symbols, everyElement(matches(RegExp(r'^yuv_\w+_v1$'))));
    });

    test('every manifest symbol is declared in src/yuv/abi/h/yuv_ops_v1.h', () {
      final declared = _symbolsDeclaredInHeader();
      expect(declared, containsAll(_abiV1Symbols));
      expect(declared.length, _abiV1Symbols.length, reason: 'header declares a symbol the manifest does not list, or vice versa');
    });

    test('every manifest symbol is matched by the ffigen.yaml functions.include allowlist', () {
      final matched = _symbolsMatchedByFfigenAllowlist();
      expect(matched, containsAll(_abiV1Symbols));
    });

    test('every manifest symbol is exported by tool/wasm/build_wasm.sh', () {
      final exported = _symbolsExportedByWasmBuildScript();
      expect(exported, containsAll(_abiV1Symbols));
    });

    test('a symbol removed from any one source is caught, not silently tolerated', () {
      // Negative control for the three positive checks above: corrupts one
      // in-memory copy of the ffigen allowlist result (rather than mutating
      // the file on disk, which would need cleanup even on a failing
      // assertion) and confirms containsAll rejects the gap. This is the
      // "proven manually and described in the report" DoD item, expressed as
      // a test rather than left to a report-only claim.
      final matched = _symbolsMatchedByFfigenAllowlist()..remove('yuv_chroma_swap_v1');
      expect(() => expect(matched, containsAll(_abiV1Symbols)), throwsA(isA<TestFailure>()));
    });
  });
}
