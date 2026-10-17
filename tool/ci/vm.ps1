param(
  [AllowEmptyCollection()]
  [string[]] $TestPath,
  [string] $Name,
  [string] $Group,
  [switch] $List
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_common.ps1')

$repositoryRoot = Get-CiRepositoryRoot
$groups = @{
  codec = 'test/yuv_serialization_test.dart'
  state = 'test/yuv_image_state_contract_test.dart'
  'pixel-format' = 'test/yuv_pixel_format_test.dart'
  presenter = 'test/yuv_frame_presenter_test.dart'
}
$hasPaths = $PSBoundParameters.ContainsKey('TestPath')
$hasGroup = $PSBoundParameters.ContainsKey('Group')
$targeted = $hasPaths -or $hasGroup -or $PSBoundParameters.ContainsKey('Name')
if ($hasPaths -and $hasGroup) { throw 'Group and TestPath are mutually exclusive.' }
if ($hasGroup -and -not $groups.ContainsKey($Group)) { throw "Unknown group: $Group" }
if ($hasPaths -and ($null -eq $TestPath -or $TestPath.Count -eq 0)) { throw 'TestPath must not be empty.' }
$selectedPaths = @(if ($hasGroup) { $groups[$Group] } elseif ($hasPaths) { $TestPath })
$testRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'test'))
foreach ($path in $selectedPaths) {
  if ([string]::IsNullOrWhiteSpace($path)) { throw 'TestPath must not contain an empty path.' }
  if (($path -split '[/\\]') -contains '..') { throw "Parent traversal is not allowed: $path" }
  $fullPath = [System.IO.Path]::GetFullPath($path, $repositoryRoot)
  if (-not $fullPath.StartsWith($testRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
      -not $fullPath.EndsWith('_test.dart', [System.StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Expected an existing *_test.dart inside test/: $path"
  }
  $entry = Get-Item -LiteralPath $fullPath -Force
  while ($null -ne $entry -and $entry.FullName -ne $repositoryRoot) {
    if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Reparse traversal is not allowed: $path"
    }
    $entry = if ($entry -is [System.IO.DirectoryInfo]) { $entry.Parent } else { $entry.Directory }
  }
}
$needsNative = -not ($selectedPaths.Count -gt 0 -and @($selectedPaths | Where-Object {
  [System.IO.Path]::GetFullPath($_, $repositoryRoot) -ne (Join-Path $testRoot 'yuv_serialization_test.dart')
}).Count -eq 0)
$testArguments = @(if ($selectedPaths.Count -gt 0) { $selectedPaths } else { '--tags'; 'smoke || contract' })
if ($PSBoundParameters.ContainsKey('Name')) { $testArguments += @('--name', $Name) }
Write-Output "VM selection: $($testArguments -join ' '); preparation: pub get; native=$needsNative; analyze=$(-not $targeted)"
if ($List) { return }
Push-Location $repositoryRoot
try {
  Invoke-CiNativeCommand flutter pub get --no-example
  if (-not $targeted) { Invoke-CiNativeCommand flutter analyze --no-fatal-infos lib test }

  if ($needsNative) {
    Add-CiPath 'D:\.important\android-sdk\cmake\3.22.1\bin'
    $nativeBuildOutput = @(New-CiNativeBuild `
      -Name 'yuv-ffi-vm-native' `
      -LibraryName 'yuv_ffi.dll')
    $nativeDllDirectory = [string]$nativeBuildOutput[-1]
    $nativeBuildOutput | Write-Output
    Add-CiPath $nativeDllDirectory
  }

  Invoke-CiFlutterTest @testArguments
} finally {
  Pop-Location
}
