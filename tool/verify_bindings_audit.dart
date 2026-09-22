#!/usr/bin/env dart
// This is a command-line audit tool, so writing to stdout is the whole point.
// ignore_for_file: avoid_print

// Audit script to verify that all Dart-used native symbols are present in the
// generated bindings.
//
// 1. Extracts the ffiBingings.* symbols actually used in lib/src/**/*.dart
// 2. Extracts the public members of the generated YuvFfiBindings class
// 3. Compares the two and reports any discrepancy
//
// Run it after regenerating bindings:
// `dart run tool/verify_bindings_audit.dart`

import 'dart:io';

Future<void> main() async {
  print('=== Bindings Audit: Verifying YuvFfiBindings ===\n');

  // Step 1: Get all used symbols from Dart code
  final usedSymbols = await _getUsedSymbols();
  print('Step 1: Found ${usedSymbols.length} symbols used in lib/src/**/*.dart');
  print('  Used symbols: ${usedSymbols.join(', ')}\n');

  // Step 2: Get all public members from generated bindings
  final generatedMembers = await _getGeneratedMembers();
  print('Step 2: Found ${generatedMembers.length} public members in YuvFfiBindings');
  print('  Generated members: ${generatedMembers.join(', ')}\n');

  // Step 3: Compare
  //
  // ABI v1 (YUV-36c, docs/api-abi-0.3-design.md sections 9-11): 11
  // `yuv_*_v1` functions have been called from the typed IO runner
  // (`yuv_abi_v1_runner.dart`, YUV-36d) since that landed, so they are
  // detected as regular used symbols -- no function allowlist is needed any
  // more. They are also the only processing functions left: YUV-52 removed
  // the 40 legacy ones from the header, the ffigen allowlist and the library.
  //
  // The 11 descriptor/options structs stay in `knownAbiV1Structs`: a struct
  // is referenced as a bare Dart type (`YuvConstFrameV1 frame = ...`, a
  // parameter type, `.ref` on a pointer), never as `ffiBingings.TypeName`,
  // so `_getUsedSymbols()` can never detect it as "used" no matter how the
  // Dart call sites evolve.
  const knownAbiV1Structs = {
    'YuvConstPlaneV1',
    'YuvMutablePlaneV1',
    'YuvConstFrameV1',
    'YuvMutableFrameV1',
    'YuvRegionOptionsV1',
    'YuvBlurOptionsV1',
    'YuvEffectOptionsV1',
    'YuvConvertOptionsV1',
    'YuvCropOptionsV1',
    'YuvFlipOptionsV1',
    'YuvRotateOptionsV1',
  };
  // Structs that are never detectable via ffiBingings.* usage (see above).
  // The legacy `YUVDef` used to carry the same exemption; YUV-52 removed the
  // type along with the legacy processing ABI, so listing it here would keep
  // excusing a name the bindings can no longer contain.
  const neverUsageDetectedStructs = knownAbiV1Structs;

  final missing = usedSymbols.where((sym) => !generatedMembers.contains(sym)).toList();
  final extra = generatedMembers.where((mem) => !usedSymbols.contains(mem) && !neverUsageDetectedStructs.contains(mem)).toList();
  final missingKnownAbiV1Structs = knownAbiV1Structs.where((name) => !generatedMembers.contains(name)).toList();

  print('Step 3: Comparison results\n');

  if (missing.isEmpty && extra.isEmpty && missingKnownAbiV1Structs.isEmpty) {
    print('✓ SUCCESS: All used symbols are present with correct names.');
    print('✓ No unexpected members found.');
    print('✓ All known ABI v1 structs are present.');
    exit(0);
  } else {
    bool hasProblem = false;

    if (missing.isNotEmpty) {
      print('✗ MISSING SYMBOLS (used in Dart but not in bindings):');
      for (final sym in missing) {
        print('  - $sym');
      }
      hasProblem = true;
    }

    if (extra.isNotEmpty) {
      print('✗ UNEXPECTED MEMBERS (in bindings but not used in Dart):');
      for (final mem in extra) {
        print('  - $mem');
      }
      hasProblem = true;
    }

    if (missingKnownAbiV1Structs.isNotEmpty) {
      print('✗ MISSING ABI V1 STRUCTS (expected but not in generated bindings):');
      for (final name in missingKnownAbiV1Structs) {
        print('  - $name');
      }
      hasProblem = true;
    }

    if (hasProblem) {
      print('\n✗ AUDIT FAILED');
      exit(1);
    }
  }
}

/// Extract all ffiBingings.* symbols used in lib/src
Future<Set<String>> _getUsedSymbols() async {
  final symbols = <String>{};
  final dartFiles = await _findFiles('lib/src', '*.dart');

  for (final file in dartFiles) {
    final content = File(file).readAsStringSync();
    final regex = RegExp(r'ffiBingings\.([a-zA-Z0-9_]+)\(');
    for (final match in regex.allMatches(content)) {
      symbols.add(match.group(1)!);
    }
  }

  return symbols;
}

/// Extract all public members from YuvFfiBindings class
Future<Set<String>> _getGeneratedMembers() async {
  final bindingsFile = 'lib/src/functions/bindings/yuv_ffi_bingings.dart';
  final content = File(bindingsFile).readAsStringSync();

  final members = <String>{};

  // Find function wrappers: "  void functionName(", "  int functionName(" or
  // "  late final functionName(". `int` covers the YUV-36 status-returning
  // ABI v1 wrappers (YuvStatus is a typedef'd int32_t, so ffigen emits `int`
  // as the Dart return type), alongside the legacy `void` wrappers.
  final funcRegex = RegExp(r'^  (void|int|late final) (\w+)\(', multiLine: true);
  for (final match in funcRegex.allMatches(content)) {
    final name = match.group(2);
    if (name != null && !name.startsWith('_')) {
      members.add(name);
    }
  }

  // Find struct declarations: "final class YuvConstFrameV1"
  final structRegex = RegExp(r'^final class (\w+)', multiLine: true);
  for (final match in structRegex.allMatches(content)) {
    final name = match.group(1);
    if (name != null) {
      members.add(name);
    }
  }

  return members;
}

/// Find all files matching pattern in directory
Future<List<String>> _findFiles(String dir, String pattern) async {
  final files = <String>[];
  final directory = Directory(dir);

  if (!await directory.exists()) {
    return files;
  }

  await for (final entity in directory.list(recursive: true)) {
    if (entity is File && _matchesPattern(entity.path, pattern)) {
      files.add(entity.path);
    }
  }

  return files;
}

/// Check if path matches glob pattern
bool _matchesPattern(String path, String pattern) {
  if (pattern == '*.dart') {
    return path.endsWith('.dart');
  }
  return true;
}
