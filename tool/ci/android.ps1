Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_common.ps1')

function Assert-ApkAbi {
  param(
    [Parameter(Mandatory)]
    [string] $ApkPath,

    [Parameter(Mandatory)]
    [string] $ExpectedAbi
  )

  if (-not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
    throw "APK is missing: $ApkPath"
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ApkPath))
  try {
    $entries = @($archive.Entries | ForEach-Object FullName)
    $abis = @($entries | ForEach-Object {
      if ($_ -match '^lib/([^/]+)/') { $Matches[1] }
    } | Sort-Object -Unique)
    if ($abis.Count -ne 1 -or $abis[0] -ne $ExpectedAbi) {
      throw "Expected only $ExpectedAbi native libraries in $ApkPath, found: $($abis -join ', ')"
    }
    if ($entries -notcontains "lib/$ExpectedAbi/libyuv_ffi.so") {
      throw "$ApkPath does not contain libyuv_ffi.so for $ExpectedAbi"
    }
  } finally {
    $archive.Dispose()
  }
}

$repositoryRoot = Get-CiRepositoryRoot
$androidSdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\.important\android-sdk' }
$adb = Join-Path $androidSdk 'platform-tools\adb.exe'
$emulator = Join-Path $androidSdk 'emulator\emulator.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
  throw "Android adb is missing: $adb"
}
if (-not (Test-Path -LiteralPath $emulator -PathType Leaf)) {
  throw "Android emulator is missing: $emulator"
}

$env:ANDROID_HOME = $androidSdk
$env:ANDROID_SDK_ROOT = $androidSdk
Add-CiPath (Split-Path -Parent $adb)
Add-CiPath (Split-Path -Parent $emulator)

$cmakeDirectory = Join-Path $androidSdk 'cmake\3.22.1\bin'
if (-not (Test-Path -LiteralPath (Join-Path $cmakeDirectory 'cmake.exe') -PathType Leaf)) {
  throw "CMake is missing: $cmakeDirectory"
}
Add-CiPath $cmakeDirectory

$nativeBuildOutput = @(New-CiNativeBuild -Name 'yuv-ffi-android-host' -LibraryName 'yuv_ffi.dll')
$nativeLibraryDirectory = [string]$nativeBuildOutput[-1]
Add-CiPath $nativeLibraryDirectory

Push-Location (Join-Path $repositoryRoot 'example')
try {
  Invoke-CiNativeCommand flutter 'pub', 'get'
  Invoke-CiNativeCommand dart 'format', '--output=none', '--set-exit-if-changed', 'integration_test/native_app_runtime_smoke_test.dart'
  Invoke-CiNativeCommand flutter 'build', 'apk', '--debug', '--target=integration_test/native_app_runtime_smoke_test.dart', '--target-platform', 'android-arm64,android-arm,android-x64', '--split-per-abi'

  Assert-ApkAbi -ApkPath 'build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk' -ExpectedAbi 'arm64-v8a'
  Assert-ApkAbi -ApkPath 'build/app/outputs/flutter-apk/app-armeabi-v7a-debug.apk' -ExpectedAbi 'armeabi-v7a'
  Assert-ApkAbi -ApkPath 'build/app/outputs/flutter-apk/app-x86_64-debug.apk' -ExpectedAbi 'x86_64'
} finally {
  Pop-Location
}

$avdNames = @(& $emulator -list-avds)
if ($LASTEXITCODE -ne 0 -or $avdNames -notcontains 'Tablet') {
  throw 'The configured x86_64 API 35 AVD Tablet is unavailable.'
}

& $adb start-server
if ($LASTEXITCODE -ne 0) {
  throw 'adb start-server failed'
}

$emulatorProcess = Start-Process -FilePath $emulator -ArgumentList @('-avd', 'Tablet', '-port', '5554', '-no-window', '-no-audio', '-no-boot-anim', '-no-snapshot', '-gpu', 'swiftshader_indirect') -WindowStyle Hidden -PassThru
try {
  & $adb -s emulator-5554 wait-for-device
  if ($LASTEXITCODE -ne 0) {
    throw 'Android emulator did not connect to adb'
  }

  $deadline = (Get-Date).AddMinutes(5)
  do {
    $bootCompleted = (& $adb -s emulator-5554 shell getprop sys.boot_completed).Trim()
    if ($bootCompleted -eq '1') { break }
    if ((Get-Date) -gt $deadline) {
      throw 'Android emulator did not finish booting within 5 minutes'
    }
    Start-Sleep -Seconds 3
  } while ($true)

  & $adb -s emulator-5554 shell settings put global window_animation_scale 0
  if ($LASTEXITCODE -ne 0) {
    throw 'Could not disable Android window animations'
  }

  & (Join-Path $PSScriptRoot 'drive.ps1') 'integration_test/native_app_runtime_smoke_test.dart' 'emulator-5554' '--no-pub'
  $targets = @(Get-ChildItem -Path (Join-Path $repositoryRoot 'example\integration_test') -Filter '*_native_test.dart' -File)
  if ($targets.Count -eq 0) {
    throw 'No native integration-test targets were found.'
  }
  foreach ($target in $targets) {
    & (Join-Path $PSScriptRoot 'drive.ps1') "integration_test/$($target.Name)" 'emulator-5554' '--no-pub'
  }
} finally {
  & $adb -s emulator-5554 emu kill
  if ($emulatorProcess -and -not $emulatorProcess.HasExited) {
    $emulatorProcess.WaitForExit(30000)
  }
}
