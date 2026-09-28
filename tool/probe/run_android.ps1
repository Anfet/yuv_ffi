[CmdletBinding()]
param(
  [string]$Serial = '',
  [ValidateSet('arm64', 'armv7')]
  [string]$Abi = 'arm64',
  [string[]]$Ops = @(),
  [switch]$Record,
  [switch]$Strict,
  [int]$CooldownSeconds = 30
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runId = [guid]::NewGuid().ToString('N')
$gitSha = (& git -C $repoRoot rev-parse HEAD).Trim().ToLowerInvariant()
$androidSdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\.important\android-sdk' }
$adb = Join-Path $androidSdk 'platform-tools\adb.exe'
if (-not (Test-Path $adb)) { throw "adb is missing: $adb" }
if ($Record) { throw 'Baseline recording requires a clean committed comparison worktree and is disabled for this runner.' }
if (-not $Serial) {
  $devices = @(& $adb devices | Select-String '\tdevice$' | ForEach-Object { ($_ -split '\t')[0] })
  if ($devices.Count -ne 1) { throw 'Pass -Serial when exactly one Android device is not connected.' }
  $Serial = $devices[0]
}

function DeviceShell([string]$Command) { (& $adb -s $Serial shell $Command 2>&1 | Out-String).Trim() }

$reasons = [System.Collections.Generic.List[string]]::new()
$power = DeviceShell 'dumpsys power'
if ($power -notmatch 'mWakefulness=Awake') { $reasons.Add('device is not awake') }
$display = DeviceShell 'dumpsys display'
if ($display -notmatch '(?m)^\s*(Display State=ON|mState=ON|mScreenState=ON)\s*$') { $reasons.Add('screen is not reported ON') }
$window = DeviceShell 'dumpsys window'
if ($window -notmatch '(?i)(mKeyguardShowing=false|isStatusBarKeyguard=false|mShowingLockscreen=false|isKeyguardShowing=false)') {
  $reasons.Add('keyguard state is not confirmed unlocked')
}
$thermal = DeviceShell 'dumpsys thermalservice'
if ($thermal -match '(?i)(severe|critical|emergency|shutdown)') { $reasons.Add('thermal throttling is reported') }

if ($reasons.Count -gt 0) {
  Write-Output "PROBE INVALID-ENV $($reasons -join '; ')"
  exit 0
}

$model = (DeviceShell 'getprop ro.product.model' -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
$deviceAbi = DeviceShell 'getprop ro.product.cpu.abi'
$expectedAbi = if ($Abi -eq 'arm64') { 'arm64-v8a' } else { 'armeabi-v7a' }
if ($deviceAbi -ne $expectedAbi -and $Abi -eq 'armv7') {
  Write-Warning "Device primary ABI is $deviceAbi; the armv7 build must still be explicitly installed before its run."
}

$target = Join-Path $repoRoot 'example\integration_test\probe_performance_test.dart'
if (-not (Test-Path $target)) {
  throw 'Android performance entrypoint is missing: example/integration_test/probe_performance_test.dart'
}

$uniqueOperations = @($Ops | Where-Object { $_ } | Sort-Object -Unique)
$expectedRunCount = if ($uniqueOperations.Count -eq 0) { 24 } else { $uniqueOperations.Count * 2 }
$sourceVerified = @(& git -C $repoRoot status --porcelain).Count -eq 0

Push-Location (Join-Path $repoRoot 'example')
try {
  $driveArguments = @(
    'drive', '--driver=test_driver/integration_test.dart', '--target=integration_test/probe_performance_test.dart', "-d$Serial", '--profile',
    "--dart-define=RA26_ANDROID_RUN_ID=$runId",
    "--dart-define=RA26_ANDROID_ABI=$expectedAbi",
    "--dart-define=RA26_GIT_SHA=$gitSha",
    "--dart-define=RA26_OPS=$($uniqueOperations -join ',')",
    "--dart-define=RA26_STRICT=$($Strict.IsPresent.ToString().ToLowerInvariant())",
    "--dart-define=RA26_COOLDOWN_SECONDS=$CooldownSeconds"
  )
  $driveOutput = & flutter @driveArguments 2>&1
  $driveExitCode = $LASTEXITCODE
  $driveText = $driveOutput | Out-String
  Write-Output $driveText
  $records = @([regex]::Matches($driveText, 'RA26_ANDROID_RESULT\s+(\{.*\})') | ForEach-Object { $_.Groups[1].Value })
  if ($records.Count -ne 1) {
    throw "Expected exactly one RA26_ANDROID_RESULT record, found $($records.Count)."
  }
  try {
    $result = $records[0] | ConvertFrom-Json
  } catch {
    throw "RA26_ANDROID_RESULT is malformed JSON: $($_.Exception.Message)"
  }
  if ($driveExitCode -ne 0 -or $result.schema -ne 1 -or $result.status -ne 'PASS' -or $result.runId -ne $runId -or `
      $result.abi -ne $expectedAbi -or $result.gitSha -ne $gitSha -or $result.buildMode -ne 'profile' -or $result.environment.valid -ne $true -or `
      $result.scenarioCount -ne $expectedRunCount -or $result.sampleCount -ne 9 -or $result.runsSha256 -notmatch '^[0-9a-f]{64}$') {
    throw "Android profile benchmark strict verdict failed: $($records[0])"
  }
  $probeLines = @([regex]::Matches($driveText, '(?m)PROBE\s+(\S+)\s+(\S+)\s+(\d+x\d+)\s+PASS\s+[\d.]+\s+ms\s+\(baseline none, .+?%\)\s+NO-BASELINE') | ForEach-Object { $_.Value })
  if ($probeLines.Count -ne $expectedRunCount -or @($probeLines | Sort-Object -Unique).Count -ne $expectedRunCount) {
    throw "Android profile benchmark expected $expectedRunCount unique PASS/NO-BASELINE probe lines, found $($probeLines.Count)."
  }
  $hostResult = [ordered]@{
    schema = 1
    status = 'PASS'
    gitSha = $gitSha
    runId = $runId
    device = $Serial
    model = $model
    abi = $expectedAbi
    buildMode = 'profile'
    sourceVerified = $sourceVerified
    environment = 'awake; screen on; keyguard unlocked; no severe thermal state'
    scenarioCount = $result.scenarioCount
    runsSha256 = $result.runsSha256
  }
  Write-Output "RA26_ANDROID_HOST_RESULT $($hostResult | ConvertTo-Json -Compress)"
} finally {
  Pop-Location
}
