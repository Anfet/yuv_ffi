Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_common.ps1')

$repositoryRoot = Get-CiRepositoryRoot
Push-Location $repositoryRoot
try {
  Add-CiPath 'D:\.important\android-sdk\cmake\3.22.1\bin'

  Invoke-CiNativeCommand flutter pub get --no-example
  Invoke-CiNativeCommand flutter analyze --no-fatal-infos lib test

  New-CiNativeBuild `
    -Name 'yuv-ffi-vm-native' `
    -LibraryName 'yuv_ffi.dll' | Out-Host
  $nativeDllDirectory = Join-Path (Get-CiTemporaryDirectory) 'yuv-ffi-vm-native\Release'
  Add-CiPath $nativeDllDirectory

  Invoke-CiNativeCommand flutter test --tags "smoke || contract"
} finally {
  Pop-Location
}
