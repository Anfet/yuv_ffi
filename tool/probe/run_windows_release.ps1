[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^[0-9a-f]{40}$')]
  [string]$GitSha,
  [string]$ResultDirectory = (Join-Path $env:TEMP 'yuv_ffi-ra26-release'),
  [string]$BaselinePath = '',
  [ValidateRange(1, 3600)]
  [int]$TimeoutSeconds = 900,
  [ValidateRange(0, 100)]
  [int]$Warmups = 3,
  [ValidateRange(1, 100)]
  [int]$Samples = 9,
  [switch]$AllowDirtySmoke
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$runId = [guid]::NewGuid().ToString('N')
$scheme = (& powercfg /getactivescheme 2>&1 | Out-String).Trim()
$expectedScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'
$powerStatuses = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue)

if ($scheme -notmatch $expectedScheme) {
  throw "RA-26 INVALID-ENV: active power scheme is not Balanced: $scheme"
}
if ($powerStatuses.Count -eq 0 -or @($powerStatuses | Where-Object { $_.PowerOnline -eq $true -and $_.Discharging -eq $false }).Count -eq 0) {
  throw 'RA-26 INVALID-ENV: external AC power is not confirmed by root\\wmi:BatteryStatus.'
}

$head = (& git -C $repoRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($head -ne $GitSha) {
  throw "GitSha $GitSha does not match HEAD $head."
}
$dirty = @(& git -C $repoRoot status --porcelain)
if ($dirty.Count -gt 0 -and -not $AllowDirtySmoke) {
  throw 'Release comparison requires a clean committed worktree. Use -AllowDirtySmoke only for a non-evidence local smoke.'
}
if ($BaselinePath -and $dirty.Count -gt 0) {
  throw 'A dirty smoke cannot compare with a baseline.'
}
if ($BaselinePath -and -not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
  throw "Baseline result is missing: $BaselinePath"
}

$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name).Trim()
$cpuId = ($cpu -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
$hostId = "windows-$cpuId-x64-release"
$resolvedResultDirectory = [IO.Path]::GetFullPath($ResultDirectory)
New-Item -ItemType Directory -Force -Path $resolvedResultDirectory | Out-Null
$resultPath = Join-Path $resolvedResultDirectory "ra26-windows-release-$runId.json"
if (Test-Path -LiteralPath $resultPath) {
  throw "Unique result path unexpectedly exists: $resultPath"
}

Push-Location (Join-Path $repoRoot 'example')
try {
  $buildArguments = @(
    'build', 'windows', '--release', '--target=probe/windows_release_benchmark.dart',
    "--dart-define=RA26_GIT_SHA=$GitSha",
    "--dart-define=RA26_RUN_ID=$runId",
    "--dart-define=RA26_RESULT_PATH=$resultPath",
    "--dart-define=RA26_HOST_ID=$hostId",
    "--dart-define=RA26_WARMUPS=$Warmups",
    "--dart-define=RA26_SAMPLES=$Samples"
  )
  if ($BaselinePath) {
    $buildArguments += "--dart-define=RA26_BASELINE_PATH=$([IO.Path]::GetFullPath($BaselinePath))"
  }
  & flutter @buildArguments
  if ($LASTEXITCODE -ne 0) { throw 'Windows release benchmark build failed.' }

  $executablePath = Join-Path (Get-Location) 'build\windows\x64\runner\Release\example.exe'
  if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Windows release benchmark executable is missing: $executablePath"
  }
  $artifactSha256 = (Get-FileHash -LiteralPath $executablePath -Algorithm SHA256).Hash.ToLowerInvariant()

  $process = Start-Process -FilePath $executablePath -WorkingDirectory (Split-Path -Parent $executablePath) -PassThru -NoNewWindow
  if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $process.Id -Force
    throw "Windows release benchmark timed out after $TimeoutSeconds seconds."
  }
  if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    throw "Windows release benchmark did not atomically create its result: $resultPath"
  }
  try {
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
  } catch {
    throw "Windows release benchmark result is malformed JSON: $($_.Exception.Message)"
  }

  if ($process.ExitCode -ne 0 -or $result.schema -ne 1 -or $result.status -ne 'PASS' -or $result.gitSha -ne $GitSha -or `
      $result.runId -ne $runId -or $result.hostId -ne $hostId -or $result.buildMode -ne 'release' -or $result.environment.valid -ne $true) {
    throw "Windows release benchmark strict verdict failed: $resultPath"
  }
  $runs = @($result.runs)
  if ($runs.Count -ne 24) {
    throw "Windows release benchmark expected 24 runs, found $($runs.Count)."
  }
  foreach ($run in $runs) {
    if ($run.verdict -ne 'PASS' -or @($run.sampleHashes).Count -ne $Samples -or @($run.sampleHashes | Where-Object { $_ -ne $run.hash }).Count -ne 0) {
      throw "Windows release benchmark run integrity failed: $($run.id)"
    }
  }
  if ($BaselinePath) {
    $baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
    if ($baseline.schema -ne 1 -or $baseline.hostId -ne $hostId -or @($baseline.runs).Count -ne 24) {
      throw 'Baseline result does not match this release host or matrix.'
    }
  }

  $hostResult = [ordered]@{
    schema = 1
    status = 'PASS'
    gitSha = $GitSha
    revision = $head
    runId = $runId
    hostId = $hostId
    buildMode = 'release'
    sourceVerified = $dirty.Count -eq 0
    baselinePath = if ($BaselinePath) { [IO.Path]::GetFullPath($BaselinePath) } else { $null }
    resultPath = $resultPath
    resultSha256 = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
    executablePath = $executablePath
    executableSha256 = $artifactSha256
    environment = 'Balanced; AC PowerOnline=True; Discharging=False'
    scenarioCount = $runs.Count
  }
  Write-Output "RA26_HOST_RESULT $($hostResult | ConvertTo-Json -Compress)"
} finally {
  Pop-Location
}
