[CmdletBinding()]
param(
  [string]$Serial = '',
  [ValidateSet('arm64')]
  [string]$Abi = 'arm64',
  [string]$ResultDirectory = (Join-Path $env:TEMP 'yuv_ffi-ra26-release'),
  [string]$BaselinePath = '',
  [ValidateRange(1, 3600)]
  [int]$TimeoutSeconds = 1800,
  [ValidateRange(0, 100)]
  [int]$Warmups = 3,
  [ValidateRange(1, 100)]
  [int]$Samples = 9,
  [ValidateRange(0, 600)]
  [int]$CooldownSeconds = 30,
  [switch]$Strict,
  [string]$ExpectedPackagePath = '',
  [ValidatePattern('^[0-9a-f]{40}$')]
  [string]$ExpectedPackageRevision = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release_android_versioning.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$exampleRoot = Join-Path $repoRoot 'example'
$packageName = 'com.example.yuv_ffi_example'
$gitSha = (& git -C $repoRoot rev-parse HEAD).Trim().ToLowerInvariant()
$initialDirty = @(& git -C $repoRoot status --porcelain)
if ($initialDirty.Count -gt 0) {
  throw 'Android release comparison requires a clean committed worktree.'
}
$packageRoot = if ($ExpectedPackagePath) { (Resolve-Path -LiteralPath $ExpectedPackagePath).Path } else { $repoRoot }
$packageRoot = [IO.Path]::GetFullPath($packageRoot)
$packageRevision = (& git -C $packageRoot rev-parse HEAD).Trim().ToLowerInvariant()
$expectedPackageRevision = if ($ExpectedPackageRevision) { $ExpectedPackageRevision } else { $gitSha }
if ($packageRevision -ne $expectedPackageRevision) {
  throw "RA-26 package revision is $packageRevision, expected $expectedPackageRevision."
}
$usesPackageOverride = -not [string]::Equals($packageRoot, $repoRoot, [StringComparison]::OrdinalIgnoreCase)
$overridePath = Join-Path $exampleRoot 'pubspec_overrides.yaml'
$temporaryOverrideCreated = $false
if ($usesPackageOverride -and (Test-Path -LiteralPath $overridePath)) {
  throw 'RA-26 baseline override must be created by this runner; remove example/pubspec_overrides.yaml before starting.'
}
if (-not $usesPackageOverride -and (Test-Path -LiteralPath $overridePath)) {
  throw 'RA-26 HEAD run must not use example/pubspec_overrides.yaml.'
}
if ($BaselinePath -and -not (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
  throw "Baseline result is missing: $BaselinePath"
}

$androidSdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\.important\android-sdk' }
$adb = Join-Path $androidSdk 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb)) { throw "adb is missing: $adb" }
$aapt = @(
  Get-ChildItem -LiteralPath (Join-Path $androidSdk 'build-tools') -Directory -ErrorAction Stop |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
)[0]
if (-not $aapt) { throw "aapt.exe is missing from Android SDK build-tools: $androidSdk" }
if (-not $Serial) {
  $devices = @(& $adb devices | Select-String '\tdevice$' | ForEach-Object { ($_ -split '\t')[0] })
  if ($devices.Count -ne 1) { throw 'Pass -Serial when exactly one Android device is not connected.' }
  $Serial = $devices[0]
}
function DeviceShell([string]$Command) { (& $adb -s $Serial shell $Command 2>&1 | Out-String).Trim() }
function Read-Ra26PackageSnapshot([string]$Moment) {
  $lines = @(& $adb -s $Serial shell dumpsys package $packageName 2>&1)
  $exitCode = $LASTEXITCODE
  $raw = $lines -join [Environment]::NewLine
  $rawPath = Join-Path $resolvedResultDirectory "package-$Moment.txt"
  [IO.File]::WriteAllText($rawPath, $raw)
  $versionCode = Get-Ra25InstalledVersionCode $raw $exitCode
  if ($raw -match '(?im)^\s*Unable to find package:') {
    throw "The existing benchmark package is not installed; firstInstallTime cannot be preserved. Snapshot: $rawPath"
  }
  $firstInstallMatches = [regex]::Matches($raw, '(?m)^\s*firstInstallTime=(.+?)\s*$')
  if ($firstInstallMatches.Count -ne 1) {
    throw "Unable to determine one installed firstInstallTime; found $($firstInstallMatches.Count). Snapshot: $rawPath"
  }
  $abiMatches = [regex]::Matches($raw, '(?m)^\s*primaryCpuAbi=([^\s]+)\s*$')
  if ($abiMatches.Count -ne 1) {
    throw "Unable to determine one installed primaryCpuAbi; found $($abiMatches.Count). Snapshot: $rawPath"
  }
  $snapshot = [ordered]@{
    packageName = $packageName
    versionCode = $versionCode
    firstInstallTime = $firstInstallMatches[0].Groups[1].Value
    primaryCpuAbi = $abiMatches[0].Groups[1].Value
    rawSnapshotPath = $rawPath
  }
  $snapshotPath = Join-Path $resolvedResultDirectory "package-$Moment.json"
  [IO.File]::WriteAllText($snapshotPath, ($snapshot | ConvertTo-Json -Depth 4))
  return [pscustomobject]$snapshot
}

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
  throw "RA-26 INVALID-ENV: $($environmentFailures -join '; ')"
}

$expectedAbi = 'arm64-v8a'
$supportedAbis = DeviceShell 'getprop ro.product.cpu.abilist'
if ($supportedAbis -notmatch [regex]::Escape($expectedAbi)) {
  throw "Device does not support ${expectedAbi}: $supportedAbis"
}
$model = (DeviceShell 'getprop ro.product.model' -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLowerInvariant()
$hostId = "android-$model-$expectedAbi-release"
$runId = [guid]::NewGuid().ToString('N')
$resolvedResultDirectory = [IO.Path]::GetFullPath($ResultDirectory)
New-Item -ItemType Directory -Force -Path $resolvedResultDirectory | Out-Null
$resultPath = Join-Path $resolvedResultDirectory "ra26-android-release-$runId.json"
if (Test-Path -LiteralPath $resultPath) { throw "Unique result path unexpectedly exists: $resultPath" }

function Read-Ra26Logcat {
  # Keep every JSON marker on one logical line; Out-String's default width
  # inserts line breaks into otherwise valid Android logcat output.
  (& $adb -s $Serial logcat -d -v raw 2>&1 | Out-String -Width 32767)
}
function Read-JsonRecords([string]$Logcat, [string]$Prefix) {
  @([regex]::Matches($Logcat, "(?m)$Prefix\s+(\{[^\r\n]*\})") | ForEach-Object { $_.Groups[1].Value })
}
function Wait-Ra26ResultLogcat {
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    $logcat = Read-Ra26Logcat
    $records = @(Read-JsonRecords $logcat 'RA26_ANDROID_RESULT')
    if ($records.Count -gt 0) { return @{ Logcat = $logcat; Records = @($records) } }
    Start-Sleep -Seconds 2
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "Android release benchmark timed out after $TimeoutSeconds seconds waiting for RA26_ANDROID_RESULT."
}
function To-Base64Url([string]$Value) {
  [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
function Write-JsonAtomically([string]$Path, [object]$Document) {
  $temporaryPath = "$Path.$runId.tmp"
  [IO.File]::WriteAllText($temporaryPath, ($Document | ConvertTo-Json -Depth 16))
  [IO.File]::Move($temporaryPath, $Path)
}
function Assert-Ra26ApkForInstall(
  [string]$Badging,
  [string[]]$ApkEntries,
  [string]$ExpectedPackageName,
  [string]$ExpectedAbi,
  [long]$ExpectedVersionCode,
  [long]$InstalledVersionCode
) {
  $packageMatches = [regex]::Matches($Badging, "(?m)^package:\s+name='([^']+)'")
  if ($packageMatches.Count -ne 1 -or [string]::IsNullOrWhiteSpace($packageMatches[0].Groups[1].Value)) {
    throw "Unable to determine one APK package name; found $($packageMatches.Count) package entries."
  }
  $packageName = $packageMatches[0].Groups[1].Value
  if ($packageName -cne $ExpectedPackageName) {
    throw "APK package metadata is $packageName, expected $ExpectedPackageName."
  }
  $versionCode = Get-Ra25ApkVersionCode $Badging
  if ($versionCode -ne $ExpectedVersionCode -or $versionCode -le $InstalledVersionCode) {
    throw "APK versionCode $versionCode does not match planned $ExpectedVersionCode above installed $InstalledVersionCode."
  }
  $abis = @($ApkEntries | ForEach-Object {
    if ($_ -match '^lib/([^/]+)/') { $Matches[1] }
  } | Sort-Object -Unique)
  if ($abis.Count -ne 1 -or $abis[0] -cne $ExpectedAbi) {
    throw "APK native ABI metadata is unexpected: $($abis -join ', '); expected only $ExpectedAbi."
  }
  if ($ApkEntries -notcontains "lib/$ExpectedAbi/libyuv_ffi.so") {
    throw "APK does not contain lib/$ExpectedAbi/libyuv_ffi.so."
  }
  return [pscustomobject]@{
    packageName = $packageName
    versionCode = $versionCode
    abis = $abis
  }
}

Start-Transcript -LiteralPath (Join-Path $resolvedResultDirectory "ra26-android-release-$runId.log") -Force | Out-Null
Push-Location $exampleRoot
try {
  if ($usesPackageOverride) {
    $packageUri = $packageRoot.Replace('\', '/')
    @('dependency_overrides:', '  yuv_ffi:', "    path: '$packageUri'") | Set-Content -LiteralPath $overridePath
    $temporaryOverrideCreated = $true
  }
  & flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Flutter pub get failed before the Android release benchmark build.' }

  $packageConfigPath = Join-Path (Get-Location) '.dart_tool\package_config.json'
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

  $beforePackage = Read-Ra26PackageSnapshot 'before'
  $versionCodePlan = Get-Ra25VersionCodePlan $beforePackage.versionCode $Abi

  $buildArguments = @(
    'build', 'apk', '--release', '--target=probe/android_release_benchmark.dart', '--target-platform=android-arm64', '--split-per-abi',
    "--build-number=$($versionCodePlan.buildNumber)",
    "--dart-define=RA26_GIT_SHA=$gitSha",
    "--dart-define=RA26_RUN_ID=$runId",
    "--dart-define=RA26_HOST_ID=$hostId",
    "--dart-define=RA26_WARMUPS=$Warmups",
    "--dart-define=RA26_SAMPLES=$Samples",
    "--dart-define=RA26_COOLDOWN_SECONDS=$CooldownSeconds"
  )
  if ($BaselinePath) {
    $baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
    $baselineDocument = [ordered]@{
      schema = $baseline.schema
      hostId = $baseline.hostId
      runs = @($baseline.runs | ForEach-Object {
        [ordered]@{
          id = $_.id
          hash = $_.hash
          medianMicros = $_.medianMicros
          spreadPercent = $_.spreadPercent
        }
      })
    } | ConvertTo-Json -Compress -Depth 4
    $buildArguments += "--dart-define=RA26_BASELINES=$(To-Base64Url $baselineDocument)"
  }
  if ($Strict) { $buildArguments += '--dart-define=RA26_STRICT=true' }
  & flutter @buildArguments
  if ($LASTEXITCODE -ne 0) { throw 'Android release benchmark APK build failed.' }

  $apkPath = Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
  if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) { throw "Release APK is missing: $apkPath" }
  $apkSha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $badgingLines = @(& $aapt dump badging $apkPath 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "Unable to read APK metadata with $aapt; installation was not attempted." }
  $badging = $badgingLines -join [Environment]::NewLine
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $apkPath))
  try {
    $apkEntries = @($archive.Entries | ForEach-Object FullName)
  } finally {
    $archive.Dispose()
  }
  try {
    $validatedApk = Assert-Ra26ApkForInstall $badging $apkEntries $packageName $expectedAbi `
      $versionCodePlan.builtVersionCode $beforePackage.versionCode
  } catch {
    throw "APK pre-install validation failed; installation was not attempted. $($_.Exception.Message)"
  }
  $apkPackageName = $validatedApk.packageName
  $apkVersionCode = $validatedApk.versionCode
  $apkAbis = $validatedApk.abis
  [IO.File]::WriteAllText((Join-Path $resolvedResultDirectory 'apk-metadata.txt'), $badging)
  $preInstallEvidence = [ordered]@{
    runId = $runId
    runnerSha = $gitSha
    packageRevision = $resolvedPackageRevision
    packagePath = $resolvedPackageRoot
    device = $Serial
    apkPath = $apkPath
    apkSha256 = $apkSha256
    apkPackageName = $apkPackageName
    apkAbis = $apkAbis
    installedVersionCode = $beforePackage.versionCode
    plannedBuildNumber = $versionCodePlan.buildNumber
    plannedVersionCode = $versionCodePlan.builtVersionCode
    firstInstallTime = $beforePackage.firstInstallTime
    installCommand = 'adb install -r'
    installAttempted = $false
  }
  $preInstallEvidencePath = Join-Path $resolvedResultDirectory 'pre-install.json'
  [IO.File]::WriteAllText($preInstallEvidencePath, ($preInstallEvidence | ConvertTo-Json -Depth 6))

  $preInstallEvidence.installAttempted = $true
  [IO.File]::WriteAllText($preInstallEvidencePath, ($preInstallEvidence | ConvertTo-Json -Depth 6))
  & $adb -s $Serial install -r $apkPath | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Release APK installation failed.' }
  $afterPackage = Read-Ra26PackageSnapshot 'after'
  if ($afterPackage.primaryCpuAbi -ne $expectedAbi -or $afterPackage.versionCode -ne $apkVersionCode) {
    throw "Installed package does not match the APK: ABI=$($afterPackage.primaryCpuAbi), versionCode=$($afterPackage.versionCode)."
  }
  if ($afterPackage.firstInstallTime -cne $beforePackage.firstInstallTime) {
    throw "firstInstallTime changed from '$($beforePackage.firstInstallTime)' to '$($afterPackage.firstInstallTime)' after adb install -r."
  }

  & $adb -s $Serial logcat -c
  if ($LASTEXITCODE -ne 0) { throw 'Unable to clear logcat before the Android release benchmark.' }
  & $adb -s $Serial shell am force-stop $packageName
  & $adb -s $Serial shell am start -n "$packageName/.MainActivity" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Unable to launch the Android release benchmark APK.' }

  $logcatResult = Wait-Ra26ResultLogcat
  if ($logcatResult.Records.Count -ne 1) { throw "Expected exactly one RA26_ANDROID_RESULT record, found $($logcatResult.Records.Count)." }
  try { $summary = @($logcatResult.Records)[0] | ConvertFrom-Json } catch { throw "RA26_ANDROID_RESULT is malformed JSON: $($_.Exception.Message)" }
  $runRecords = @(Read-JsonRecords $logcatResult.Logcat 'RA26_ANDROID_RUN')
  if ($runRecords.Count -ne 24) { throw "Android release benchmark expected 24 RA26_ANDROID_RUN records, found $($runRecords.Count)." }
  $runs = @($runRecords | ForEach-Object { $_ | ConvertFrom-Json })
  $uniqueRunIds = @($runs | ForEach-Object id | Sort-Object -Unique)
  if ($summary.schema -ne 1 -or $summary.status -ne 'PASS' -or $summary.gitSha -ne $gitSha -or $summary.runId -ne $runId -or `
      $summary.hostId -ne $hostId -or $summary.buildMode -ne 'release' -or $summary.environment.valid -ne $true -or `
      $summary.scenarioCount -ne 24 -or $summary.sampleCount -ne $Samples -or $summary.runsSha256 -notmatch '^[0-9a-f]{64}$' -or $uniqueRunIds.Count -ne 24) {
    throw "Android release benchmark strict verdict failed: $($logcatResult.Records[0])"
  }
  foreach ($run in $runs) {
    if ($run.verdict -ne 'PASS' -or @($run.sampleHashes).Count -ne $Samples -or @($run.sampleHashes | Where-Object { $_ -ne $run.hash }).Count -ne 0) {
      throw "Android release benchmark run integrity failed: $($run.id)"
    }
  }

  $document = [ordered]@{
    schema = 1
    status = 'PASS'
    gitSha = $gitSha
    revision = $gitSha
    runId = $runId
    hostId = $hostId
    buildMode = 'release'
    packagePath = $resolvedPackageRoot
    packageRevision = $resolvedPackageRevision
    packageOverridden = $usesPackageOverride
    packageConfigPath = $packageConfigPath
    baselinePath = if ($BaselinePath) { [IO.Path]::GetFullPath($BaselinePath) } else { $null }
    device = $Serial
    model = $model
    abi = $expectedAbi
    supportedAbis = $supportedAbis
    environment = 'awake; screen on; keyguard unlocked; no severe thermal state'
    apkPath = $apkPath
    apkSha256 = $apkSha256
    installedVersionCodeBefore = $beforePackage.versionCode
    installedVersionCodeAfter = $afterPackage.versionCode
    firstInstallTimeBefore = $beforePackage.firstInstallTime
    firstInstallTimeAfter = $afterPackage.firstInstallTime
    packageSnapshotBefore = $beforePackage
    packageSnapshotAfter = $afterPackage
    apkMetadataPath = Join-Path $resolvedResultDirectory 'apk-metadata.txt'
    preInstallEvidencePath = $preInstallEvidencePath
    logPath = Join-Path $resolvedResultDirectory "ra26-android-release-$runId.log"
    summary = $summary
    runs = $runs
  }
  Write-JsonAtomically $resultPath $document
  $hostSummary = [pscustomobject]$document | Select-Object schema,status,gitSha,runId,hostId,buildMode,packageRevision,packageOverridden,baselinePath,device,model,abi,apkSha256
  Write-Output "RA26_ANDROID_HOST_RESULT $($hostSummary | ConvertTo-Json -Compress)"
  Write-Output "RA26_ANDROID_RESULT_PATH $resultPath"
} finally {
  Pop-Location
  Stop-Transcript | Out-Null
  if ($temporaryOverrideCreated) {
    Remove-Item -LiteralPath $overridePath -Force -ErrorAction SilentlyContinue
  }
  # The runner required a clean checkout, so these are its own pub-generated
  # files and restoring them keeps the next comparison source-verified.
  & git -C $repoRoot restore --worktree -- example/pubspec.lock example/android/app/src/main/kotlin/com/example/yuv_ffi_example/MainActivity.kt example/windows/flutter/generated_plugin_registrant.cc example/windows/flutter/generated_plugin_registrant.h example/windows/flutter/generated_plugins.cmake
}
