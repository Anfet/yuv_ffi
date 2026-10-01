[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidatePattern('^[0-9a-f]{40}$')]
  [string]$GitSha,
  [string]$ResultDirectory = (Join-Path $env:TEMP 'yuv_ffi-ra26-release'),
  [string]$EvidenceDirectory = (Join-Path $env:TEMP 'yuv_ffi-ra26-release'),
  [string]$BaselinePath = '',
  [ValidateRange(1, 3600)]
  [int]$TimeoutSeconds = 900,
  [ValidateRange(0, 100)]
  [int]$Warmups = 3,
  [ValidateRange(1, 100)]
  [int]$Samples = 9,
  [switch]$Strict,
  [switch]$AllowDirtySmoke,
  [string]$ExpectedPackagePath = '',
  [ValidatePattern('^[0-9a-f]{40}$')]
  [string]$ExpectedPackageRevision = '',
  [switch]$ValidatePackageOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$exampleRoot = Join-Path $repoRoot 'example'
$runId = [guid]::NewGuid().ToString('N')
$expectedScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'

function Get-Ra26PowerSnapshot {
  $schemeOutput = (& powercfg /getactivescheme 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "RA-26 INVALID-ENV: powercfg /getactivescheme failed: $schemeOutput"
  }
  $guidMatch = [regex]::Match($schemeOutput, '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b')
  $nameMatch = [regex]::Match($schemeOutput, '\((?<name>[^)]*)\)')
  if (-not $guidMatch.Success -or -not $nameMatch.Success -or [string]::IsNullOrWhiteSpace($nameMatch.Groups['name'].Value)) {
    throw "RA-26 INVALID-ENV: active power scheme did not provide a GUID and name: $schemeOutput"
  }

  $statuses = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue)
  if ($statuses.Count -eq 0) {
    throw 'RA-26 INVALID-ENV: root\\wmi:BatteryStatus returned no AC readings.'
  }
  $readings = @(
    $statuses | ForEach-Object {
      [ordered]@{
        instanceName = $_.InstanceName
        powerOnline = [bool]$_.PowerOnline
        discharging = [bool]$_.Discharging
      }
    }
  )
  [ordered]@{
    schemeGuid = $guidMatch.Value.ToLowerInvariant()
    schemeName = $nameMatch.Groups['name'].Value.Trim()
    schemeRaw = $schemeOutput
    batteryStatus = $readings
  }
}

function Assert-Ra26BalancedAc([object]$Snapshot, [string]$Moment) {
  if ($Snapshot.schemeGuid -ne $expectedScheme) {
    throw "RA-26 INVALID-ENV: active power scheme $Moment is $($Snapshot.schemeGuid) ($($Snapshot.schemeName)), expected Balanced $expectedScheme."
  }
  if (@($Snapshot.batteryStatus | Where-Object { $_.powerOnline -ne $true -or $_.discharging -ne $false }).Count -gt 0) {
    throw "RA-26 INVALID-ENV: external AC power $Moment is not confirmed by every root\\wmi:BatteryStatus reading."
  }
}

function Write-Ra26JsonAtomically([string]$Path, [object]$Document) {
  if (Test-Path -LiteralPath $Path) {
    throw "RA-26 evidence path already exists: $Path"
  }
  $temporaryPath = "$Path.$runId.tmp"
  if (Test-Path -LiteralPath $temporaryPath) {
    throw "RA-26 temporary evidence path already exists: $temporaryPath"
  }
  try {
    [IO.File]::WriteAllText($temporaryPath, "$($Document | ConvertTo-Json -Depth 10)`n", [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path
  } finally {
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
  }
}

$head = (& git -C $repoRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($head -ne $GitSha) {
  throw "GitSha $GitSha does not match HEAD $head."
}
$packageRoot = if ($ExpectedPackagePath) { (Resolve-Path -LiteralPath $ExpectedPackagePath).Path } else { $repoRoot }
$packageRoot = [IO.Path]::GetFullPath($packageRoot)
$packageRevision = (& git -C $packageRoot rev-parse HEAD).Trim().ToLowerInvariant()
$expectedPackageRevision = if ($ExpectedPackageRevision) { $ExpectedPackageRevision } else { $head }
if ($packageRevision -ne $expectedPackageRevision) {
  throw "RA-26 package revision is $packageRevision, expected $expectedPackageRevision."
}
$usesPackageOverride = -not [string]::Equals($packageRoot, $repoRoot, [StringComparison]::OrdinalIgnoreCase)
$overridePath = Join-Path $exampleRoot 'pubspec_overrides.yaml'
$temporaryOverrideCreated = $false
$initialDirty = @(& git -C $repoRoot status --porcelain)
if ($initialDirty.Count -gt 0 -and -not $AllowDirtySmoke) {
  throw 'Release comparison requires a clean committed worktree. Use -AllowDirtySmoke only for a non-evidence local smoke.'
}
if ($BaselinePath -and $initialDirty.Count -gt 0) {
  throw 'A dirty smoke cannot compare with a baseline.'
}
if ($BaselinePath -and -not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
  throw "Baseline result is missing: $BaselinePath"
}
if ($usesPackageOverride -and (Test-Path -LiteralPath $overridePath)) {
  throw "RA-26 baseline override must be created by this runner; remove $overridePath before starting."
}
if (-not $usesPackageOverride -and (Test-Path -LiteralPath $overridePath)) {
  throw "RA-26 HEAD run must not use $overridePath."
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
$resolvedEvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
$resolvedRepoRoot = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/')
$repoPrefix = "$resolvedRepoRoot$([IO.Path]::DirectorySeparatorChar)"
if ([string]::Equals($resolvedEvidenceDirectory, $resolvedRepoRoot, [StringComparison]::OrdinalIgnoreCase) -or `
    $resolvedEvidenceDirectory.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
  throw "EvidenceDirectory must be outside the source checkout: $resolvedEvidenceDirectory"
}
New-Item -ItemType Directory -Force -Path $resolvedEvidenceDirectory | Out-Null
$receiptPath = Join-Path $resolvedEvidenceDirectory "ra26-windows-release-$runId-host.json"
if (Test-Path -LiteralPath $receiptPath) {
  throw "Unique host receipt path unexpectedly exists: $receiptPath"
}

Push-Location $exampleRoot
try {
  if ($usesPackageOverride) {
    $packageUri = $packageRoot.Replace('\', '/')
    @(
      'dependency_overrides:',
      '  yuv_ffi:',
      "    path: '$packageUri'"
    ) | Set-Content -LiteralPath $overridePath
    $temporaryOverrideCreated = $true
  }

  if (-not $ValidatePackageOnly) {
    & flutter clean
    if ($LASTEXITCODE -ne 0) { throw 'Flutter clean failed before the release benchmark build.' }
  }
  & flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Flutter pub get failed before the release benchmark build.' }

  $packageConfigPath = Join-Path (Get-Location) '.dart_tool\package_config.json'
  if (-not (Test-Path -LiteralPath $packageConfigPath -PathType Leaf)) {
    throw "RA-26 package config is missing: $packageConfigPath"
  }
  $packageConfig = Get-Content -LiteralPath $packageConfigPath -Raw | ConvertFrom-Json
  $packageEntries = @($packageConfig.packages | Where-Object { $_.name -eq 'yuv_ffi' })
  if ($packageEntries.Count -ne 1 -or [string]::IsNullOrWhiteSpace($packageEntries[0].rootUri)) {
    throw 'RA-26 package config must resolve exactly one yuv_ffi package root.'
  }
  $packageRootUri = [uri]$packageEntries[0].rootUri
  $packageRootPath = if ($packageRootUri.IsAbsoluteUri) {
    $packageRootUri.LocalPath
  } else {
    Join-Path (Split-Path -Parent $packageConfigPath) $packageEntries[0].rootUri
  }
  $resolvedPackageRoot = [IO.Path]::GetFullPath(
    (Resolve-Path -LiteralPath $packageRootPath).Path
  ).TrimEnd('\', '/')
  if (-not [string]::Equals($resolvedPackageRoot, $packageRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "RA-26 package config resolved yuv_ffi to $resolvedPackageRoot, expected $packageRoot."
  }
  $resolvedPackageRevision = (& git -C $resolvedPackageRoot rev-parse HEAD).Trim().ToLowerInvariant()
  if ($resolvedPackageRevision -ne $expectedPackageRevision) {
    throw "RA-26 resolved package revision is $resolvedPackageRevision, expected $expectedPackageRevision."
  }
  $packageProvenance = [ordered]@{
    appGitSha = $head
    packageConfigEntry = $packageEntries[0]
    resolvedPackageRoot = $resolvedPackageRoot
    packageRevision = $resolvedPackageRevision
    packageOverridden = $usesPackageOverride
    packageConfigPath = $packageConfigPath
  }
  if ($ValidatePackageOnly) {
    Write-Output "RA26_PACKAGE_PROVENANCE $($packageProvenance | ConvertTo-Json -Compress)"
    return
  }

  $buildArguments = @(
    'build', 'windows', '--release', '--target=probe/windows_release_benchmark.dart',
    "--dart-define=RA26_GIT_SHA=$GitSha",
    "--dart-define=RA26_RUN_ID=$runId",
    "--dart-define=RA26_RESULT_PATH=$resultPath",
    "--dart-define=RA26_HOST_ID=$hostId",
    "--dart-define=RA26_WARMUPS=$Warmups",
    "--dart-define=RA26_SAMPLES=$Samples"
  )
  if ($Strict) {
    $buildArguments += '--dart-define=RA26_STRICT=true'
  }
  if ($BaselinePath) {
    $buildArguments += "--dart-define=RA26_BASELINE_PATH=$([IO.Path]::GetFullPath($BaselinePath))"
  }
  & flutter @buildArguments
  if ($LASTEXITCODE -ne 0) { throw 'Windows release benchmark build failed.' }

  $executablePath = Join-Path (Get-Location) 'build\windows\x64\runner\Release\example.exe'
  if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Windows release benchmark executable is missing: $executablePath"
  }
  $releaseDirectory = Split-Path -Parent $executablePath
  $dllPaths = @(Get-ChildItem -LiteralPath $releaseDirectory -Filter 'yuv_ffi.dll' -File)
  if ($dllPaths.Count -ne 1) {
    throw "RA-26 release artifact requires exactly one yuv_ffi.dll in $releaseDirectory; found $($dllPaths.Count)."
  }
  $executableSha256 = (Get-FileHash -LiteralPath $executablePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $dllPath = $dllPaths[0].FullName
  $dllSha256 = (Get-FileHash -LiteralPath $dllPath -Algorithm SHA256).Hash.ToLowerInvariant()

  $preLaunchPower = Get-Ra26PowerSnapshot
  Assert-Ra26BalancedAc $preLaunchPower 'immediately before launch'
  $process = Start-Process -FilePath $executablePath -WorkingDirectory (Split-Path -Parent $executablePath) -PassThru -NoNewWindow
  if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-Process -Id $process.Id -Force
    throw "Windows release benchmark timed out after $TimeoutSeconds seconds."
  }
  $postExitPower = Get-Ra26PowerSnapshot
  Assert-Ra26BalancedAc $postExitPower 'immediately after process exit'
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
  $uniqueRunIds = @($runs | ForEach-Object { $_.id } | Sort-Object -Unique)
  if ($runs.Count -ne 24 -or $uniqueRunIds.Count -ne 24) {
    throw "Windows release benchmark expected 24 unique runs, found $($runs.Count) runs and $($uniqueRunIds.Count) IDs."
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

  $verdictSha256 = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $hostReceipt = [ordered]@{
    schema = 1
    status = 'PASS'
    runId = $runId
    appCommit = $head
    package = $packageProvenance
    host = [ordered]@{
      cpuModel = $cpu
      hostId = $hostId
    }
    artifacts = [ordered]@{
      releaseDirectory = $releaseDirectory
      executablePath = $executablePath
      executableSha256 = $executableSha256
      dllPath = $dllPath
      dllSha256 = $dllSha256
    }
    verdict = [ordered]@{
      path = $resultPath
      sha256 = $verdictSha256
      runId = $result.runId
    }
    power = [ordered]@{
      beforeLaunch = $preLaunchPower
      afterExit = $postExitPower
    }
    sourceVerified = $initialDirty.Count -eq 0
    baselinePath = if ($BaselinePath) { [IO.Path]::GetFullPath($BaselinePath) } else { $null }
    scenarioCount = $runs.Count
  }
  Write-Ra26JsonAtomically $receiptPath $hostReceipt
  Write-Output "RA26_HOST_RECEIPT $receiptPath"
  Write-Output "RA26_HOST_RESULT $($hostReceipt | ConvertTo-Json -Depth 10 -Compress)"
} finally {
  Pop-Location
  if ($temporaryOverrideCreated) {
    Remove-Item -LiteralPath $overridePath -Force -ErrorAction SilentlyContinue
  }
  # The runner required a clean checkout, so these are its own pub-generated
  # files and restoring them keeps the next comparison source-verified.
  & git -C $repoRoot restore --worktree -- example/pubspec.lock example/windows/flutter/generated_plugin_registrant.cc example/windows/flutter/generated_plugin_registrant.h example/windows/flutter/generated_plugins.cmake
}
