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
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
  throw "Android adb is missing: $adb"
}

$env:ANDROID_HOME = $androidSdk
$env:ANDROID_SDK_ROOT = $androidSdk
Add-CiPath (Split-Path -Parent $adb)

& $adb start-server
if ($LASTEXITCODE -ne 0) {
  throw 'adb start-server failed'
}

$deviceLines = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() })
$authorized = @($deviceLines | Where-Object { $_ -match '^(\S+)\tdevice$' } | ForEach-Object { ($_ -split "`t")[0] })
if ($env:ANDROID_SERIAL) {
  $serial = if ($authorized -contains $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL } else { $null }
} else {
  $serial = if ($authorized.Count -eq 1) { $authorized[0] } else { $null }
}
if (-not $serial) {
  throw "BLOCKED: connect exactly one authorized Android device (adb state 'device') or set ANDROID_SERIAL; adb devices: $($deviceLines -join ' | ')"
}

function Invoke-DeviceShell([string] $Command) {
  $text = (& $adb -s $serial shell $Command 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
  if ($LASTEXITCODE -ne 0) {
    throw "adb shell '$Command' failed on ${serial}: $text"
  }
  $text
}

if ((Invoke-DeviceShell 'dumpsys power') -notmatch 'mWakefulness=Awake' -or
    (Invoke-DeviceShell 'dumpsys window') -notmatch '(?i)(mKeyguardShowing=false|isStatusBarKeyguard=false|mShowingLockscreen=false|isKeyguardShowing=false)') {
  throw "BLOCKED: turn on and unlock the screen of $serial"
}

$abilist = (Invoke-DeviceShell 'getprop ro.product.cpu.abilist').Trim()
if ($abilist -notmatch 'arm64-v8a') {
  throw "BLOCKED: $serial does not support arm64-v8a ($abilist)"
}
$model = (Invoke-DeviceShell 'getprop ro.product.model').Trim()
$androidRelease = (Invoke-DeviceShell 'getprop ro.build.version.release').Trim()
Write-Output "Android device: $serial; model=$model; android=$androidRelease; abis=$abilist"

$cmakeDirectory = Join-Path $androidSdk 'cmake\3.22.1\bin'
if (-not (Test-Path -LiteralPath (Join-Path $cmakeDirectory 'cmake.exe') -PathType Leaf)) {
  throw "CMake is missing: $cmakeDirectory"
}
Add-CiPath $cmakeDirectory

. (Join-Path $repositoryRoot 'tool\probe\release_android_versioning.ps1')

$packageName = 'com.example.yuv_ffi_example'
$smokeTarget = 'integration_test/native_app_runtime_smoke_test.dart'
$nativeTargets = @(Get-ChildItem -Path (Join-Path $repositoryRoot 'example\integration_test') -Filter '*_native_test.dart' -File)
if ($nativeTargets.Count -eq 0) {
  throw 'No native integration-test targets were found.'
}
$targets = @($smokeTarget) + @($nativeTargets | ForEach-Object { "integration_test/$($_.Name)" })

$nativeBuildOutput = @(New-CiNativeBuild -Name 'yuv-ffi-android-host' -LibraryName 'yuv_ffi.dll')
$nativeLibraryDirectory = [string]$nativeBuildOutput[-1]
Add-CiPath $nativeLibraryDirectory

Push-Location (Join-Path $repositoryRoot 'example')
try {
  Invoke-CiNativeCommand flutter 'pub', 'get'
  Invoke-CiNativeCommand dart 'format', '--output=none', '--set-exit-if-changed', $smokeTarget
  Invoke-CiNativeCommand flutter 'build', 'apk', '--debug', "--target=$smokeTarget", '--target-platform', 'android-arm64,android-arm', '--split-per-abi'

  Assert-ApkAbi -ApkPath 'build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk' -ExpectedAbi 'arm64-v8a'
  Assert-ApkAbi -ApkPath 'build/app/outputs/flutter-apk/app-armeabi-v7a-debug.apk' -ExpectedAbi 'armeabi-v7a'

  $apk = 'build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk'
  foreach ($target in $targets) {
    $packageInfo = (& $adb -s $serial shell dumpsys package $packageName 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
    $installed = Get-Ra25InstalledVersionCode $packageInfo $LASTEXITCODE
    $buildNumber = $installed + 1
    Invoke-CiNativeCommand flutter 'build', 'apk', '--debug', "--target=$target", '--target-platform', 'android-arm64', '--split-per-abi', "--build-number=$buildNumber"
    Assert-ApkAbi -ApkPath $apk -ExpectedAbi 'arm64-v8a'

    $installOutput = @(& $adb -s $serial install -r (Resolve-Path -LiteralPath $apk).Path 2>&1 | ForEach-Object { $_.ToString() })
    if ($LASTEXITCODE -ne 0 -or -not ($installOutput | Where-Object { $_ -match 'Success' })) {
      throw "BLOCKED: adb install -r failed on $serial for ${packageName}: $($installOutput | Select-Object -Last 1). The script never removes apps or clears data; Engineer decides."
    }

    & (Join-Path $PSScriptRoot 'drive.ps1') $target $serial '--no-pub' '--keep-app-running' "--use-application-binary=$apk"
  }
} finally {
  Pop-Location
  & $adb -s $serial shell am force-stop $packageName
}

Write-Output "PASS Android checks on $serial ($model): APK ABIs arm64-v8a, armeabi-v7a; device targets: $($targets.Count)"
