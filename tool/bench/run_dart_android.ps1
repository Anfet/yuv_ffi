<# Builds one exact public-Dart package as a release APK and records its 18 MEAS-02 rows. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('v024', 'abi_v1')] [string] $Version,
    [string] $SourceRef,
    [Parameter(Mandatory)] [string] $OutCsv,
    [string] $Serial = '8B1X11QLW',
    [int] $TimeoutSec = 1800,
    [string] $OutRoot = (Join-Path $env:TEMP 'yuv_ffi_dart_bench_android')
)

$ErrorActionPreference = 'Stop'
$csvHeader = 'platform,machine,round,version,sha,src_tree_id,scenario_id,op,src_fmt,dst_fmt,width,height,params,layout,level,status,reason,warmup,n,min_ms,median_ms,p95_or_max_ms,upper_kind,mean_ms,stdev_ms,spread,checksum_sha256,raw_ms,started_at,finished_at,compiler,flags,power_plan,affinity'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if (-not $SourceRef) { $SourceRef = if ($Version -eq 'v024') { '0.2.4' } else { '35c516e216fef8d5ed4ef379d38655fc643f738d' } }
$sha = (& git -C $repo rev-parse "$SourceRef^{commit}").Trim()
$tree = (& git -C $repo rev-parse "${sha}:src").Trim()
$expectedTree = if ($Version -eq 'v024') { 'eba076b4cc9a0d7a686b61edbbb8101da9270356' } else { '9029ff28d9834c069f41159d122b36ed6d9d4968' }
if ($tree -ne $expectedTree) { throw "Unexpected src tree: $tree" }
if ((& adb -s $Serial get-state).Trim() -ne 'device') { throw "Android device $Serial is unavailable" }
if (Test-Path -LiteralPath $OutCsv) { throw "Use a new OutCsv path: $OutCsv" }

$worktree = Join-Path $OutRoot "source_$Version"; $app = Join-Path $OutRoot "app_$Version"; $rawRows = Join-Path $OutRoot "android_$Version.rows.tmp"
New-Item -ItemType Directory -Force -Path $OutRoot, (Split-Path -Parent $OutCsv) | Out-Null
if (-not (Test-Path -LiteralPath $worktree)) { & git -C $repo worktree add --detach $worktree $sha; if ($LASTEXITCODE) { throw 'worktree add failed' } }
if ((& git -C $worktree rev-parse HEAD).Trim() -ne $sha -or (& git -C $worktree status --porcelain)) { throw "Invalid source worktree $worktree" }
if (-not (Test-Path -LiteralPath (Join-Path $app 'android'))) { & flutter create --platforms=android --project-name "yuv_bench_$Version" $app; if ($LASTEXITCODE) { throw 'flutter create failed' } }
$appGradle = Join-Path $app 'android\app\build.gradle.kts'
if (Test-Path -LiteralPath $appGradle) {
    $gradle = (Get-Content -LiteralPath $appGradle -Raw).Replace('minSdk = flutter.minSdkVersion', 'minSdk = 26')
    [IO.File]::WriteAllText($appGradle, $gradle, [Text.UTF8Encoding]::new($false))
}
$sourcePath = $worktree.Replace('\', '/')
$pubspec = @"
name: yuv_bench_$Version
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  flutter:
    sdk: flutter
  crypto: ^3.0.6
  yuv_ffi:
    path: '$sourcePath'
"@
[IO.File]::WriteAllText((Join-Path $app 'pubspec.yaml'), $pubspec, [Text.UTF8Encoding]::new($false))
foreach ($file in @('bench_matrix_core.dart', 'bench_flip_images.dart', "bench_mobile_$Version.dart")) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot "dart\$file") -Destination (Join-Path $app "lib\$file") -Force }
Copy-Item -LiteralPath (Join-Path $app "lib\bench_mobile_$Version.dart") -Destination (Join-Path $app 'lib\main.dart') -Force

Push-Location $app
try {
    & flutter pub get; if ($LASTEXITCODE) { throw 'flutter pub get failed' }
    & flutter build apk --release --dart-define=BENCH_SHA=$sha --dart-define=BENCH_TREE=$tree; if ($LASTEXITCODE) { throw 'flutter build apk failed' }
    $apk = Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk'
    & adb -s $Serial install -r $apk; if ($LASTEXITCODE) { throw 'adb install -r failed' }
    $since = (Get-Date).ToString('MM-dd HH:mm:ss.fff')
    & adb -s $Serial shell monkey -p "com.example.yuv_bench_$Version" 1 | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        $matches = @(& adb -s $Serial logcat -d -v time -T $since yuv_bench:I '*:S' | Select-String 'YUV_BENCH_CSV:' | ForEach-Object { $_.ToString().Substring($_.ToString().IndexOf('YUV_BENCH_CSV:') + 14) })
        if ($matches.Count -lt 18) { Start-Sleep -Milliseconds 500 }
    } while ($matches.Count -lt 18 -and (Get-Date) -lt $deadline)
    if ($matches.Count -ne 18) { throw "Expected 18 benchmark rows in logcat, got $($matches.Count) within $TimeoutSec seconds" }
    [IO.File]::WriteAllLines($rawRows, @($csvHeader) + $matches, [Text.UTF8Encoding]::new($false))
    $rows = @(Import-Csv -LiteralPath $rawRows)
    $expected = @('FLIP.I420.V', 'FLIP.NV12.V', 'FLIP.BGRA.V') | ForEach-Object { $scenario = $_; @('1920x1080', '4000x3000') | ForEach-Object { $size = $_; 1..3 | ForEach-Object { "$scenario|$size|$_" } } }
    $actual = @($rows | ForEach-Object { "$($_.scenario_id)|$($_.width)x$($_.height)|$($_.round)" })
    if ($rows.Count -ne 18 -or @($actual | Sort-Object -Unique).Count -ne 18 -or @(Compare-Object $expected $actual).Count -ne 0) { throw 'CSV does not contain the complete MEAS-02 matrix' }
    foreach ($row in $rows) {
        if ($row.platform -ne 'android' -or $row.machine -ne 'Pixel_3_8B1X11QLW' -or $row.version -ne $Version -or $row.sha -ne $sha -or $row.src_tree_id -ne $tree -or $row.op -ne 'flip' -or $row.params -ne 'direction=V' -or $row.layout -ne 'tight' -or $row.level -ne 'dart' -or $row.status -notin @('OK', 'UNSUPPORTED')) { throw "Invalid Android CSV metadata/status: $($row | ConvertTo-Json -Compress)" }
    }
    [IO.File]::WriteAllLines($OutCsv, @($csvHeader) + $matches, [Text.UTF8Encoding]::new($false))
    Write-Host "Android ${Version}: 18 validated rows -> $OutCsv"
} finally {
    Pop-Location
    Remove-Item -LiteralPath $rawRows -Force -ErrorAction SilentlyContinue
}
