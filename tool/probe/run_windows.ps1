[CmdletBinding()]
param(
  [string[]]$Ops = @(),
  [switch]$Record,
  [switch]$Strict,
  [int]$Warmups = 3,
  [int]$Samples = 9
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$resultDirectory = Join-Path $env:TEMP 'yuv_ffi-probe'
$resultPath = Join-Path $resultDirectory 'probe-result.json'

function Write-InvalidEnvironment([string[]]$Reasons, [string]$PowerScheme) {
  New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
  @{
    schema = 1
    status = 'INVALID-ENV'
    platform = 'windows'
    environment = @{ valid = $false; reasons = $Reasons; powerScheme = $PowerScheme }
    runs = @()
  } | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $resultPath
  Write-Output "PROBE INVALID-ENV $($Reasons -join '; ')"
  Write-Output "PROBE result $resultPath"
}

$reasons = [System.Collections.Generic.List[string]]::new()
$scheme = (& powercfg /getactivescheme 2>&1 | Out-String).Trim()
if ($scheme -notmatch '381b4222-f694-41f0-9685-ff5bb260df2e') {
  $reasons.Add("active power scheme is not the approved Balanced scheme: $scheme")
}

$batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
if ($batteries.Count -gt 0) {
  $powerStatuses = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue)
  if ($powerStatuses.Count -eq 0 -or @($powerStatuses | Where-Object { $_.PowerOnline -eq $true -and $_.Discharging -eq $false }).Count -eq 0) {
    $batteryStatuses = $batteries.BatteryStatus -join ','
    $reasons.Add("external AC power with no battery discharge could not be confirmed (Win32_Battery status: $batteryStatuses)")
  }
}

if ($reasons.Count -gt 0) {
  Write-InvalidEnvironment $reasons $scheme
  exit 0
}

$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name).Trim()
$cpuId = ($cpu -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
$hostId = "windows-$cpuId-x64-jit"
$baselinePath = Join-Path $repoRoot "test\probe\baseline\$hostId.json"

$env:PROBE_TIMING = '1'
$env:PROBE_HOST_ID = $hostId
$env:PROBE_BUILD_MODE = 'jit'
$env:PROBE_ENV_VALID = '1'
$env:PROBE_ENV_DETAILS = "Balanced scheme; PowerOnline=True; Discharging=False; $scheme"
$env:PROBE_RESULT_PATH = $resultPath
$env:PROBE_BASELINE_PATH = $baselinePath
$env:PROBE_WARMUPS = $Warmups
$env:PROBE_SAMPLES = $Samples
$env:PROBE_OPS = $Ops -join ','
if ($Record) { $env:PROBE_RECORD = '1' } else { Remove-Item Env:PROBE_RECORD -ErrorAction SilentlyContinue }
if ($Strict) { $env:PROBE_STRICT = '1' } else { Remove-Item Env:PROBE_STRICT -ErrorAction SilentlyContinue }

Push-Location $repoRoot
try {
  flutter test test/probe/probe_performance_test.dart --reporter expanded
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
