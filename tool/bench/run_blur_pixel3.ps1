<# Runs one public Dart blur operation per Android Release invocation on Pixel 3. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('box', 'mean', 'gaussian')] [string] $Operation,
    [Parameter(Mandatory)] [string] $PackageSourcePath,
    [string] $Variant = 'rgb',
    [string] $Serial = '8B1X11QLW',
    [int] $TimeoutSec = 600,
    [string] $OutDirectory = (Join-Path $PSScriptRoot '..\\..\\doc\\perf\\results\\blur_raw')
)

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'blur_runner'
$source = (Resolve-Path -LiteralPath $PackageSourcePath).Path
$fixture = Join-Path $source 'tool\\bench\\fixtures\\blur_reference_1477x1065.png'
$stagedFixture = Join-Path $runner 'assets\\blur_reference_1477x1065.png'
$overrides = Join-Path $runner 'pubspec_overrides.yaml'
$packageName = 'com.yuvffi.bench.blur_runner'
if (-not (Test-Path -LiteralPath $fixture)) { throw "Fixture does not exist: $fixture" }
if (-not (Test-Path -LiteralPath (Join-Path $source 'pubspec.yaml'))) { throw "Package source does not contain pubspec.yaml: $source" }
if ((& adb -s $Serial get-state).Trim() -ne 'device') { throw "Android device $Serial is unavailable" }
$packageSha = (& git -C $source rev-parse HEAD).Trim()
$sourceSha = (& git -C $source rev-parse "HEAD:src").Trim()
$nativeSource = @{
    box = 'src/yuv/abi/yuv_box_blur_v1.c'
    mean = 'src/yuv/abi/yuv_mean_blur_v1.c'
    gaussian = 'src/yuv/abi/yuv_gaussian_blur_v1.c'
}[$Operation]
$candidateSourceSha = (Get-FileHash -LiteralPath (Join-Path $source $nativeSource) -Algorithm SHA256).Hash.ToLowerInvariant()
$fixtureSha = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
$sourcePathYaml = $source.Replace('\\', '/')
$buildParameters = "android-release-aot;operation=$Operation;radius=10;sigma=10;warmup=2;samples=7"
New-Item -ItemType Directory -Force -Path $OutDirectory, (Split-Path -Parent $stagedFixture) | Out-Null
[IO.File]::WriteAllText($overrides, "dependency_overrides:`n  yuv_ffi:`n    path: '$sourcePathYaml'`n", [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $fixture -Destination $stagedFixture -Force
Push-Location $runner
try {
    & flutter pub get; if ($LASTEXITCODE) { throw 'flutter pub get failed' }
    & flutter build apk --release "--dart-define=BLUR_OPERATION=$Operation" "--dart-define=BLUR_PACKAGE_SHA=$packageSha" "--dart-define=BLUR_SOURCE_SHA=$sourceSha" "--dart-define=BLUR_BUILD_PARAMETERS=$buildParameters" "--dart-define=BLUR_VARIANT=$Variant" "--dart-define=BLUR_CANDIDATE_SOURCE_SHA=$candidateSourceSha"
    if ($LASTEXITCODE) { throw 'flutter build apk --release failed' }
    $apk = Join-Path $runner 'build\\app\\outputs\\flutter-apk\\app-release.apk'
    & adb -s $Serial install -r $apk; if ($LASTEXITCODE) { throw 'adb install -r failed' }
    $started = Get-Date; $since = $started.ToString('MM-dd HH:mm:ss.fff')
    & adb -s $Serial shell am start -n "$packageName/.MainActivity" | Out-Null
    $deadline = $started.AddSeconds($TimeoutSec); $results = @()
    do {
        $lines = @(& adb -s $Serial logcat -d -v time -T $since flutter:I '*:S')
        $results = @($lines | Select-String -SimpleMatch 'YUV_BLUR_RESULT:')
        if ($results.Count -eq 2) { break }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    $stamp = $started.ToString('yyyyMMdd-HHmmss'); $rawPath = Join-Path $OutDirectory "$stamp-$Operation.log"
    [IO.File]::WriteAllLines($rawPath, $lines, [Text.UTF8Encoding]::new($false))
    if ($results.Count -ne 2) {
        $lastStage = @($lines | Select-String -SimpleMatch 'YUV_BLUR_STAGE:' | Select-Object -Last 1)
        $stageText = if ($lastStage.Count) { $lastStage[0].ToString() } else { 'no YUV_BLUR_STAGE line observed' }
        throw "No result within $TimeoutSec seconds. Last stage: $stageText. Raw output: $rawPath"
    }
    $json = @($results | ForEach-Object { $line = $_.ToString(); $line.Substring($line.IndexOf('YUV_BLUR_RESULT:') + 'YUV_BLUR_RESULT:'.Length) })
    $resultPath = Join-Path $OutDirectory "$stamp-$Operation.jsonl"
    [IO.File]::WriteAllLines($resultPath, $json, [Text.UTF8Encoding]::new($false))
    Write-Host "fixture_sha256=$fixtureSha"; Write-Host "result=$resultPath"; Write-Host "raw_log=$rawPath"
} finally {
    Pop-Location
    Remove-Item -LiteralPath $overrides, $stagedFixture -Force -ErrorAction SilentlyContinue
}
