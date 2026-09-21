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
  // ABI v1 (YUV-36c, docs/api-abi-0.3-design.md sections 9-11): 11 `yuv_*_v1`
  // functions and 11 descriptor/options structs are generated but not yet
  // called from lib/src/**/*.dart -- the typed IO runner is YUV-36d.
  //
  // The two are tracked separately rather than in one list, because
  // _getUsedSymbols() below can only ever confirm the first group:
  //
  //   - functions ARE eventually detectable: they are always called through
  //     `ffiBingings.<name>(...)`, which the regex below matches. Once
  //     YUV-36d lands, `knownAbiV1Functions` can be deleted and these 11 will
  //     be picked up by the normal used/generated comparison, same as the 40
  //     legacy symbols today.
  //   - structs are NEVER detectable this way, not even after YUV-36d: a
  //     struct is referenced as a bare Dart type (`YuvConstFrameV1 frame =
  //     ...`, a parameter type, `.ref` on a pointer), never as
  //     `ffiBingings.TypeName`. This is not new to YUV-36c -- `YUVDef` has
  //     the same property and was already hardcoded out of `extra` below
  //     before this task touched the file. `knownAbiV1Structs` documents
  //     that permanently, it is not scheduled for removal.
  //
  // Both lists are checked in both directions: `generatedMembers` must
  // contain every name listed (an entry disappearing from ffigen.yaml or the
  // generated file is a regression), and nothing here stands in for a
  // "used" symbol going missing from generatedMembers -- that still fails
  // via `missing` below once real call sites exist.
  const knownAbiV1Functions = {
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
  };
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
  // Structs that are never detectable via ffiBingings.* usage (see above):
  // known ABI v1 structs, plus the legacy YUVDef this script already carried
  // that exemption for.
  const neverUsageDetectedStructs = {'YUVDef', ...knownAbiV1Structs};

  final missing = usedSymbols.where((sym) => !generatedMembers.contains(sym)).toList();
  final extra = generatedMembers
      .where((mem) => !usedSymbols.contains(mem) && !neverUsageDetectedStructs.contains(mem) && !knownAbiV1Functions.contains(mem))
      .toList();
  final missingFromKnownAbiV1 = {...knownAbiV1Functions, ...knownAbiV1Structs}.where((name) => !generatedMembers.contains(name)).toList();

  print('Step 3: Comparison results\n');

  if (missing.isEmpty && extra.isEmpty && missingFromKnownAbiV1.isEmpty) {
    print('✓ SUCCESS: All used symbols are present with correct names.');
    print('✓ No unexpected members found.');
    print('✓ All known ABI v1 functions and structs are present.');
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

    if (missingFromKnownAbiV1.isNotEmpty) {
      print('✗ MISSING ABI V1 SURFACE (expected but not in generated bindings):');
      for (final name in missingFromKnownAbiV1) {
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
    final regex = RegExp(r'ffiBingings\.([a-zA-Z0-9_]+)');
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

  // Find struct declarations: "final class YUVDef"
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
