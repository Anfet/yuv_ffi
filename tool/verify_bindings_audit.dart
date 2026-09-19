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
  final missing = usedSymbols.where((sym) => !generatedMembers.contains(sym)).toList();
  final extra = generatedMembers.where((mem) => !usedSymbols.contains(mem) && mem != 'YUVDef').toList();

  print('Step 3: Comparison results\n');

  if (missing.isEmpty && extra.isEmpty) {
    print('✓ SUCCESS: All used symbols are present with correct names.');
    print('✓ No unexpected members found.');
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

  // Find function wrappers: "  void functionName(" or "  <type> functionName("
  final funcRegex = RegExp(r'^  (void|late final) (\w+)\(', multiLine: true);
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
