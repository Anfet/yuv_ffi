Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_common.ps1')

$repositoryRoot = Get-CiRepositoryRoot

$cmakeDirectory = 'D:\.important\android-sdk\cmake\3.22.1\bin'
if (-not (Test-Path -LiteralPath (Join-Path $cmakeDirectory 'cmake.exe') -PathType Leaf)) {
  throw "CMake is missing: $cmakeDirectory"
}
Add-CiPath $cmakeDirectory

$nativeBuildOutput = @(New-CiNativeBuild -Name 'yuv-ffi-windows' -LibraryName 'yuv_ffi.dll')
$nativeLibraryDirectory = [string]$nativeBuildOutput[-1]
$nativeBuildOutput | Write-Output
Add-CiPath $nativeLibraryDirectory

Push-Location $repositoryRoot
try {
  Invoke-CiNativeCommand flutter 'pub', 'get'
  Invoke-CiNativeCommand flutter 'test', '--tags', 'probe', '--reporter', 'expanded'
  Invoke-CiNativeCommand flutter 'test', 'test/reference_native_conversions_test.dart', '--reporter', 'expanded'
} finally {
  Pop-Location
}

Push-Location (Join-Path $repositoryRoot 'example')
try {
  Invoke-CiNativeCommand flutter 'pub', 'get'
  Invoke-CiNativeCommand flutter 'build', 'windows', '--release'
} finally {
  Pop-Location
}

& (Join-Path $PSScriptRoot 'drive.ps1') 'integration_test/native_app_runtime_smoke_test.dart' 'windows' '--no-pub'

$targets = @(Get-ChildItem -Path (Join-Path $repositoryRoot 'example\\integration_test') -Filter '*_native_test.dart' -File)
if ($targets.Count -eq 0) {
  throw 'No native integration-test targets were found.'
}

foreach ($target in $targets) {
  & (Join-Path $PSScriptRoot 'drive.ps1') "integration_test/$($target.Name)" 'windows' '--no-pub'
}
