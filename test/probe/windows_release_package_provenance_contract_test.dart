@Tags(['release'])

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('tool/probe/run_windows_release.ps1').readAsStringSync();

  test('accepts a baseline package only through a controlled temporary override', () {
    expect(source, contains(r'[string]$ExpectedPackagePath'));
    expect(source, contains("RA-26 baseline override must be created by this runner"));
    expect(source, contains("'dependency_overrides:'"));
    expect(source, contains("'  yuv_ffi:'"));
    expect(source, contains(r'Remove-Item -LiteralPath $overridePath'));
  });

  test('rejects a package config whose path or revision differs from the requested tag', () {
    expect(source, contains('RA-26 package config resolved yuv_ffi to'));
    expect(source, contains('RA-26 resolved package revision is'));
    expect(source, contains(r'git -C $resolvedPackageRoot rev-parse HEAD'));
    expect(source, contains(r'$packageRootUri.IsAbsoluteUri'));
    expect(source, contains(r'Join-Path (Split-Path -Parent $packageConfigPath)'));
    expect(source, contains(r").TrimEnd('\', '/')"));
  });

  test('records both app and resolved package provenance in the strict host result', () {
    expect(source, contains(r'appGitSha = $packageProvenance.appGitSha'));
    expect(source, contains(r'packagePath = $packageProvenance.packagePath'));
    expect(source, contains(r'packageRevision = $packageProvenance.packageRevision'));
    expect(source, contains(r'packageOverridden = $packageProvenance.packageOverridden'));
  });
}
