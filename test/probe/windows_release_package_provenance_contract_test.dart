@Tags(['release'])
library;

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
    expect(source, contains(r'& flutter clean'));
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
    expect(source, contains(r'packageConfigEntry = $packageEntries[0]'));
    expect(source, contains(r'resolvedPackageRoot = $resolvedPackageRoot'));
    expect(source, contains(r'packageRevision = $resolvedPackageRevision'));
    expect(source, contains(r'packageOverridden = $usesPackageOverride'));
  });

  test('writes a receipt linked to the verdict and release artifacts', () {
    expect(source, contains(r'[string]$EvidenceDirectory'));
    expect(source, contains(r"-Filter 'yuv_ffi.dll' -File"));
    expect(source, contains(r'found $($dllPaths.Count)'));
    expect(source, contains(r'dllSha256 = $dllSha256'));
    expect(source, contains(r'sha256 = $verdictSha256'));
    expect(source, contains(r'Write-Ra26JsonAtomically $receiptPath $hostReceipt'));
  });

  test('records and enforces the observed pre-launch and post-exit power readings', () {
    expect(source, contains(r'schemeGuid = $guidMatch.Value.ToLowerInvariant()'));
    expect(source, contains("schemeName = \$nameMatch.Groups['name'].Value.Trim()"));
    expect(source, contains(r'batteryStatus = $readings'));
    expect(source, contains(r'Assert-Ra26BalancedAc $preLaunchPower'));
    expect(source, contains(r'Assert-Ra26BalancedAc $postExitPower'));
  });
}
