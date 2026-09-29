[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^[0-9a-f]{40}$')]
  [string]$GitSha,
  [string]$Serial = '',
  [ValidateSet('arm64', 'armv7')]
  [string]$Abi = 'arm64',
  [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$androidSdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\.important\android-sdk' }
$adb = Join-Path $androidSdk 'platform-tools\adb.exe'
$packageName = 'com.example.yuv_ffi_example'
$activityName = "$packageName/.MainActivity"
$expectedAbi = if ($Abi -eq 'arm64') { 'arm64-v8a' } else { 'armeabi-v7a' }
$targetPlatform = if ($Abi -eq 'arm64') { 'android-arm64' } else { 'android-arm' }
$apkName = if ($Abi -eq 'arm64') { 'app-arm64-v8a-release.apk' } else { 'app-armeabi-v7a-release.apk' }
$runId = [guid]::NewGuid().ToString('N')

if (-not (Test-Path $adb)) { throw "adb is missing: $adb" }
if ($TimeoutSeconds -le 0) { throw 'TimeoutSeconds must be positive.' }
if (-not $Serial) {
  $devices = @(& $adb devices | Select-String '\tdevice$' | ForEach-Object { ($_ -split '\t')[0] })
  if ($devices.Count -ne 1) { throw 'Pass -Serial when exactly one Android device is not connected.' }
  $Serial = $devices[0]
}

function DeviceShell([string]$Command) { (& $adb -s $Serial shell $Command 2>&1 | Out-String).Trim() }

$environmentFailures = [System.Collections.Generic.List[string]]::new()
$power = DeviceShell 'dumpsys power'
if ($power -notmatch 'mWakefulness=Awake') { $environmentFailures.Add('device is not awake') }
$display = DeviceShell 'dumpsys display'
if ($display -notmatch '(?m)^\s*(Display State=ON|mState=ON|mScreenState=ON)\s*$') { $environmentFailures.Add('screen is not reported ON') }
$window = DeviceShell 'dumpsys window'
if ($window -notmatch '(?i)(mKeyguardShowing=false|isStatusBarKeyguard=false|mShowingLockscreen=false|isKeyguardShowing=false)') {
  $environmentFailures.Add('keyguard state is not confirmed unlocked')
}
$thermal = DeviceShell 'dumpsys thermalservice'
if ($thermal -match '(?i)(severe|critical|emergency|shutdown)') { $environmentFailures.Add('thermal throttling is reported') }
if ($environmentFailures.Count -gt 0) {
  throw "RA-25 INVALID-ENV: $($environmentFailures -join '; ')"
}

$model = DeviceShell 'getprop ro.product.model'
$androidVersion = DeviceShell 'getprop ro.build.version.release'
$supportedAbis = DeviceShell 'getprop ro.product.cpu.abilist'
if ($supportedAbis -notmatch [regex]::Escape($expectedAbi)) {
  throw "Device does not support ${expectedAbi}: $supportedAbis"
}

Push-Location (Join-Path $repoRoot 'example')
try {
  flutter build apk --release --target=probe/release_probe.dart --target-platform=$targetPlatform --split-per-abi `
    --dart-define=RA25_GIT_SHA=$GitSha --dart-define=RA25_RUN_ID=$runId --dart-define=RA25_EXPECTED_ABI=$expectedAbi
  if ($LASTEXITCODE -ne 0) { throw 'Release APK build failed.' }

  $apkPath = Join-Path (Get-Location) "build\app\outputs\flutter-apk\$apkName"
  if (-not (Test-Path $apkPath)) { throw "Release APK is missing: $apkPath" }
  $apkHash = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $apkPath))
  try {
    $entries = @($archive.Entries | ForEach-Object FullName)
    $abis = @($entries | ForEach-Object {
      if ($_ -match '^lib/([^/]+)/') { $Matches[1] }
    } | Sort-Object -Unique)
    if ($abis.Count -ne 1 -or $abis[0] -ne $expectedAbi) {
      throw "Expected only $expectedAbi native libraries, found: $($abis -join ', ')"
    }
    if ($entries -notcontains "lib/$expectedAbi/libyuv_ffi.so") {
      throw "Release APK does not contain lib/$expectedAbi/libyuv_ffi.so"
    }
  } finally {
    $archive.Dispose()
  }

  & $adb -s $Serial uninstall $packageName | Out-Null
  & $adb -s $Serial install $apkPath
  if ($LASTEXITCODE -ne 0) { throw 'Release APK installation failed.' }

  $packageInfo = DeviceShell "dumpsys package $packageName"
  if ($packageInfo -notmatch "primaryCpuAbi=$([regex]::Escape($expectedAbi))") {
    throw "Installed package primaryCpuAbi is not $expectedAbi."
  }

  & $adb -s $Serial logcat -c
  if ($LASTEXITCODE -ne 0) { throw 'Unable to clear logcat before the release probe run.' }
  & $adb -s $Serial shell am force-stop $packageName
  & $adb -s $Serial shell am start -n $activityName | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Unable to launch the release probe APK.' }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $records = @()
  do {
    Start-Sleep -Seconds 1
    $logcat = (& $adb -s $Serial logcat -d -v raw 2>&1 | Out-String)
    $records = @($logcat -split "`r?`n" | ForEach-Object {
      if ($_ -match 'RA25_RESULT\s+(\{.*\})\s*$') { $Matches[1] }
    } | Where-Object { $_ })
  } while ($records.Count -eq 0 -and (Get-Date) -lt $deadline)

  if ($records.Count -eq 1) {
    Start-Sleep -Seconds 2
    $logcat = (& $adb -s $Serial logcat -d -v raw 2>&1 | Out-String)
    $records = @($logcat -split "`r?`n" | ForEach-Object {
      if ($_ -match 'RA25_RESULT\s+(\{.*\})\s*$') { $Matches[1] }
    } | Where-Object { $_ })
  }

  if ($records.Count -ne 1) {
    throw "Expected exactly one RA25_RESULT logcat record, found $($records.Count)."
  }
  try {
    $verdict = $records[0] | ConvertFrom-Json
  } catch {
    throw "RA25_RESULT is not valid JSON: $($_.Exception.Message)"
  }
  if ($verdict.schema -ne 1 -or $verdict.gitSha -ne $GitSha -or $verdict.runId -ne $runId -or $verdict.abi -ne $expectedAbi -or `
      $verdict.smoke -ne 'PASS' -or $verdict.probe -ne 'PASS' -or $verdict.caseCount -ne 1188) {
    throw "RA25_RESULT failed strict validation: $($records[0])"
  }

  $hostResult = [ordered]@{
    schema = 1
    gitSha = $GitSha
    runId = $runId
    abi = $expectedAbi
    smoke = 'PASS'
    probe = 'PASS'
    caseCount = 1188
    apkSha256 = $apkHash
    apkPath = $apkPath
    model = $model
    android = $androidVersion
    supportedAbis = $supportedAbis
    device = $Serial
  }
  Write-Output "RA25_HOST_RESULT $($hostResult | ConvertTo-Json -Compress)"
} finally {
  Pop-Location
}
