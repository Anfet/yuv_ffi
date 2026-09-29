[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^[0-9a-f]{40}$')]
  [string]$GitSha,
  [string]$Serial = '',
  [ValidateSet('arm64', 'armv7')]
  [string]$Abi = 'arm64',
  [int]$TimeoutSeconds = 300,
  [string]$RunId = '',
  [string]$EvidenceDirectory = (Join-Path $env:TEMP 'yuv_ffi-ra25-release'),
  [string]$ValidateLogcatPath = '',
  [string]$ValidateAdbPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$actualGitSha = (& git -C $repoRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $actualGitSha -notmatch '^[0-9a-f]{40}$') {
  throw "Could not resolve the Git SHA for source checkout: $repoRoot"
}
if ($actualGitSha -ne $GitSha) {
  throw "GitSha $GitSha does not match actual source checkout HEAD $actualGitSha."
}
$sourceDirty = @(& git -C $repoRoot status --porcelain)
if ($LASTEXITCODE -ne 0) { throw "Could not inspect source checkout status: $repoRoot" }
if ($sourceDirty.Count -gt 0) {
  throw 'RA-25 requires a clean source checkout before the release APK build.'
}
if (-not $RunId) { $RunId = [guid]::NewGuid().ToString('N') }
if ($RunId -notmatch '^[0-9a-f]{32}$') { throw 'RunId must be a 32-character lowercase run ID.' }

function Read-Ra25ResultMarker([string]$Logcat) {
  $markers = [System.Collections.Generic.List[object]]::new()
  foreach ($line in ($Logcat -split "`r?`n")) {
    foreach ($match in [regex]::Matches($line, '(?<![A-Za-z0-9_])RA25_RESULT(?![A-Za-z0-9_])')) {
      $markers.Add([pscustomobject]@{
        raw = $line
        payload = $line.Substring($match.Index + $match.Length).Trim()
      })
    }
  }
  if ($markers.Count -ne 1) {
    throw "Expected exactly one RA25_RESULT logcat marker, found $($markers.Count)."
  }
  $marker = $markers[0]
  if ([string]::IsNullOrWhiteSpace($marker.payload)) {
    throw 'RA25_RESULT marker is malformed: JSON payload is missing.'
  }
  try {
    $verdict = $marker.payload | ConvertFrom-Json
  } catch {
    throw "RA25_RESULT marker is malformed JSON: $($_.Exception.Message)"
  }
  return [pscustomobject]@{ marker = $marker; verdict = $verdict }
}

function Assert-Ra25Verdict($Verdict, [string]$ExpectedGitSha, [string]$ExpectedRunId, [string]$ExpectedAbi, [string]$RawMarker) {
  $expectedNames = @('schema', 'gitSha', 'runId', 'abi', 'smoke', 'probe', 'caseCount')
  $actualNames = @($Verdict.PSObject.Properties.Name)
  if ($actualNames.Count -ne $expectedNames.Count -or @($actualNames | Where-Object { $_ -cnotin $expectedNames }).Count -gt 0) {
    throw "RA25_RESULT has an unexpected schema: $RawMarker"
  }

  $exactString = {
    param($Value, [string]$Expected)
    $Value -is [string] -and [string]::Equals($Value, $Expected, [StringComparison]::Ordinal)
  }
  if ($Verdict.schema -isnot [Int64] -or $Verdict.schema -ne 1 -or $Verdict.caseCount -isnot [Int64] -or $Verdict.caseCount -ne 1188 -or `
      -not (& $exactString $Verdict.gitSha $ExpectedGitSha) -or -not (& $exactString $Verdict.runId $ExpectedRunId) -or `
      -not (& $exactString $Verdict.abi $ExpectedAbi) -or -not (& $exactString $Verdict.smoke 'PASS') -or `
      -not (& $exactString $Verdict.probe 'PASS')) {
    throw "RA25_RESULT failed strict validation: $RawMarker"
  }
}

function Wait-Ra25ResultLogcat([scriptblock]$ReadLogcat, [int]$TimeoutSeconds, [int]$SettleSeconds) {
  if ($TimeoutSeconds -le 0) { throw 'TimeoutSeconds must be positive.' }
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $markerCount = 0
  $logcat = ''
  do {
    Start-Sleep -Seconds 1
    $logcat = & $ReadLogcat
    $markerCount = [regex]::Matches($logcat, '(?<![A-Za-z0-9_])RA25_RESULT(?![A-Za-z0-9_])').Count
  } while ($markerCount -eq 0 -and (Get-Date) -lt $deadline)

  if ($markerCount -gt 0 -and $SettleSeconds -gt 0) {
    Start-Sleep -Seconds $SettleSeconds
    $logcat = & $ReadLogcat
  }
  return $logcat
}

function Read-Ra25AdbLogcat([string]$Adb, [string]$DeviceSerial) {
  $logcat = (& $Adb -s $DeviceSerial logcat -d -v raw 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) { throw "Unable to read logcat from $DeviceSerial." }
  return $logcat
}

if ($ValidateLogcatPath -and $ValidateAdbPath) {
  throw 'Pass only one logcat validation source.'
}
if ($ValidateLogcatPath) {
  if (-not (Test-Path -LiteralPath $ValidateLogcatPath -PathType Leaf)) {
    throw "ValidateLogcatPath is missing: $ValidateLogcatPath"
  }
  $validationExpectedAbi = if ($Abi -eq 'arm64') { 'arm64-v8a' } else { 'armeabi-v7a' }
  $logcat = Wait-Ra25ResultLogcat { Get-Content -LiteralPath $ValidateLogcatPath -Raw } $TimeoutSeconds 0
  $resultMarker = Read-Ra25ResultMarker $logcat
  Assert-Ra25Verdict $resultMarker.verdict $GitSha $RunId $validationExpectedAbi $resultMarker.marker.raw
  Write-Output "RA25_LOGCAT_RESULT $($resultMarker.verdict | ConvertTo-Json -Compress)"
  return
}
if ($ValidateAdbPath) {
  if (-not (Test-Path -LiteralPath $ValidateAdbPath -PathType Leaf)) {
    throw "ValidateAdbPath is missing: $ValidateAdbPath"
  }
  $validationExpectedAbi = if ($Abi -eq 'arm64') { 'arm64-v8a' } else { 'armeabi-v7a' }
  $logcat = Wait-Ra25ResultLogcat { Read-Ra25AdbLogcat $ValidateAdbPath 'ra25-fake-device' } $TimeoutSeconds 0
  $resultMarker = Read-Ra25ResultMarker $logcat
  Assert-Ra25Verdict $resultMarker.verdict $GitSha $RunId $validationExpectedAbi $resultMarker.marker.raw
  Write-Output "RA25_LOGCAT_RESULT $($resultMarker.verdict | ConvertTo-Json -Compress)"
  return
}

$androidSdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\.important\android-sdk' }
$adb = Join-Path $androidSdk 'platform-tools\adb.exe'
$packageName = 'com.example.yuv_ffi_example'
$activityName = "$packageName/.MainActivity"
$expectedAbi = if ($Abi -eq 'arm64') { 'arm64-v8a' } else { 'armeabi-v7a' }
$targetPlatform = if ($Abi -eq 'arm64') { 'android-arm64' } else { 'android-arm' }
$apkName = if ($Abi -eq 'arm64') { 'app-arm64-v8a-release.apk' } else { 'app-armeabi-v7a-release.apk' }
$resolvedEvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
$resolvedRepoRoot = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/')
$repoPrefix = "$resolvedRepoRoot\"
if ([string]::Equals($resolvedEvidenceDirectory, $resolvedRepoRoot, [StringComparison]::OrdinalIgnoreCase) -or `
    $resolvedEvidenceDirectory.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "EvidenceDirectory must be outside the source checkout: $resolvedEvidenceDirectory"
}
New-Item -ItemType Directory -Force -Path $resolvedEvidenceDirectory | Out-Null

if (-not (Test-Path $adb)) { throw "adb is missing: $adb" }
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

  $logcat = Wait-Ra25ResultLogcat { Read-Ra25AdbLogcat $adb $Serial } $TimeoutSeconds 2
  $resultMarker = Read-Ra25ResultMarker $logcat
  $verdict = $resultMarker.verdict
  Assert-Ra25Verdict $verdict $GitSha $runId $expectedAbi $resultMarker.marker.raw

  $hostEvidencePath = Join-Path $resolvedEvidenceDirectory "ra25-$Abi-$runId-host.json"
  $deviceEvidencePath = Join-Path $resolvedEvidenceDirectory "ra25-$Abi-$runId-device.json"
  if ((Test-Path -LiteralPath $hostEvidencePath) -or (Test-Path -LiteralPath $deviceEvidencePath)) {
    throw "RA-25 evidence path already exists for run $runId."
  }
  $hostEvidence = [ordered]@{
    schema = 1
    kind = 'RA25_HOST_RESULT'
    gitSha = $GitSha
    revision = $actualGitSha
    runId = $runId
    abi = $expectedAbi
    apk = [ordered]@{
      path = $apkPath
      sha256 = $apkHash
      zipEntries = $entries
      nativeAbis = $abis
      requiredEntry = "lib/$expectedAbi/libyuv_ffi.so"
    }
  }
  $deviceEvidence = [ordered]@{
    schema = 1
    kind = 'RA25_DEVICE_RESULT'
    gitSha = $GitSha
    runId = $runId
    abi = $expectedAbi
    device = [ordered]@{
      serial = $Serial
      model = $model
      android = $androidVersion
      supportedAbis = $supportedAbis
    }
    logcatMarker = [ordered]@{
      raw = $resultMarker.marker.raw
      payload = $resultMarker.marker.payload
      verdict = $verdict
    }
  }
  [IO.File]::WriteAllText($hostEvidencePath, ($hostEvidence | ConvertTo-Json -Depth 8))
  [IO.File]::WriteAllText($deviceEvidencePath, ($deviceEvidence | ConvertTo-Json -Depth 8))

  $hostResult = [ordered]@{
    schema = 1
    gitSha = $GitSha
    revision = $actualGitSha
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
    hostEvidencePath = $hostEvidencePath
    deviceEvidencePath = $deviceEvidencePath
  }
  Write-Output "RA25_HOST_RESULT $($hostResult | ConvertTo-Json -Compress)"
} finally {
  Pop-Location
}
