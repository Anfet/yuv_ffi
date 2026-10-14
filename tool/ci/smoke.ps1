Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_common.ps1')

$repositoryRoot = Get-CiRepositoryRoot
if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot 'pubspec.yaml') -PathType Leaf)) {
  throw "Repository root does not contain pubspec.yaml: $repositoryRoot"
}

$temporaryDirectory = Get-CiTemporaryDirectory
if (-not (Test-Path -LiteralPath $temporaryDirectory -PathType Container)) {
  throw "Temporary directory does not exist: $temporaryDirectory"
}

$flutterRoot = Get-CiFlutterRoot
if (-not (Test-Path -LiteralPath $flutterRoot -PathType Container)) {
  throw "Flutter root does not exist: $flutterRoot"
}

$cmakeDirectory = 'D:\.important\android-sdk\cmake\3.22.1\bin'
if (-not (Test-Path -LiteralPath (Join-Path $cmakeDirectory 'cmake.exe') -PathType Leaf)) {
  throw "CMake is missing: $cmakeDirectory"
}
Add-CiPath $cmakeDirectory

$expectedBuildDirectory = Get-CiNativeBuildDirectory -Name 'yuv-ffi-smoke-native' -Configuration 'Release'
$nativeBuildOutput = @(New-CiNativeBuild -Name 'yuv-ffi-smoke-native' -LibraryName 'yuv_ffi.dll')
$nativeLibraryDirectory = [string]$nativeBuildOutput[-1]
$nativeBuildOutput | Write-Output
$expectedLibraryDirectory = if ($IsWindows) { Join-Path $expectedBuildDirectory 'Release' } else { $expectedBuildDirectory }
if ($nativeLibraryDirectory -ne $expectedLibraryDirectory) {
  throw "Native helper returned $nativeLibraryDirectory instead of $expectedLibraryDirectory"
}
Add-CiPath $nativeLibraryDirectory

$driveScript = Join-Path $PSScriptRoot 'drive.ps1'
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
  $driveScript,
  [ref] $null,
  [ref] $parseErrors
)
if ($parseErrors.Count -ne 0) {
  throw "PowerShell parser rejected ${driveScript}: $($parseErrors.Message -join '; ')"
}

Write-Output 'CI helper smoke passed.'
