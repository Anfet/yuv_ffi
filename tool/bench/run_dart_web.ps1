<# Builds a release JS Flutter app with the package WASM C backend and records 18 Chrome rows. #>
[CmdletBinding()]
param(
  [string] $SourceRef = '35c516e216fef8d5ed4ef379d38655fc643f738d',
  [Parameter(Mandatory)] [string] $OutCsv,
  [int] $TimeoutSec = 1800,
  [string] $OutRoot = (Join-Path $env:TEMP 'yuv_ffi_dart_bench_web')
)
$ErrorActionPreference = 'Stop'
$csvHeader = 'platform,machine,round,version,sha,src_tree_id,scenario_id,op,src_fmt,dst_fmt,width,height,params,layout,level,status,reason,warmup,n,min_ms,median_ms,p95_or_max_ms,upper_kind,mean_ms,stdev_ms,spread,checksum_sha256,raw_ms,started_at,finished_at,compiler,flags,power_plan,affinity'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$sha = (& git -C $repo rev-parse "$SourceRef^{commit}").Trim(); $tree = (& git -C $repo rev-parse "${sha}:src").Trim()
if ($sha -ne '35c516e216fef8d5ed4ef379d38655fc643f738d' -or $tree -ne '9029ff28d9834c069f41159d122b36ed6d9d4968') { throw 'Web runner is ABI v1 only. Record legacy-Web evidence separately.' }
if (Test-Path -LiteralPath $OutCsv) { throw "Use a new OutCsv path: $OutCsv" }
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
if (-not (Test-Path -LiteralPath $chrome)) { throw "Chrome executable not found: $chrome" }
$gitExe = (Get-Command git -CommandType Application -ErrorAction Stop).Source
$gitDirectory = Split-Path -Parent $gitExe
$gitBashCandidates = @(
  (Join-Path (Split-Path -Parent $gitDirectory) 'bin\bash.exe'),
  (Join-Path $gitDirectory 'bash.exe')
)
$gitBash = $gitBashCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $gitBash) { throw "Git Bash was not found beside git.exe: $gitExe" }
$source = Join-Path $OutRoot 'source_abi_v1'; $app = Join-Path $OutRoot 'app_abi_v1'; $rawRows = Join-Path $OutRoot 'web.rows.tmp'
New-Item -ItemType Directory -Force -Path $OutRoot, (Split-Path -Parent $OutCsv) | Out-Null
if (-not (Test-Path -LiteralPath $source)) { & git -C $repo worktree add --detach $source $sha; if ($LASTEXITCODE) { throw 'worktree add failed' } }
if ((& git -C $source rev-parse HEAD).Trim() -ne $sha -or (& git -C $source status --porcelain)) { throw "Invalid source worktree $source" }
if (-not (Test-Path -LiteralPath (Join-Path $app 'web'))) { & flutter create --platforms=web --project-name yuv_bench_web $app; if ($LASTEXITCODE) { throw 'flutter create failed' } }
$sourcePath = $source.Replace('\', '/')
$pubspec = @"
name: yuv_bench_web
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
foreach ($file in @('bench_matrix_core.dart', 'bench_flip_images.dart', 'bench_web_abi_v1.dart')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot "dart\$file") -Destination (Join-Path $app "lib\$file") -Force }
Copy-Item -LiteralPath (Join-Path $app 'lib\bench_web_abi_v1.dart') -Destination (Join-Path $app 'lib\main.dart') -Force
Push-Location $source
try { & $gitBash -lc './tool/wasm/build_wasm.sh --profile release'; if ($LASTEXITCODE) { throw 'package WASM release build failed' } } finally { Pop-Location }
Push-Location $app
try { & flutter pub get; if ($LASTEXITCODE) { throw 'flutter pub get failed' }; & flutter build web --release --dart-define=BENCH_SHA=$sha --dart-define=BENCH_TREE=$tree; if ($LASTEXITCODE) { throw 'Flutter release JS build failed' } } finally { Pop-Location }
$root = Join-Path $app 'build\web'
$server = Start-Process python -ArgumentList @('-m', 'http.server', '8765', '--directory', $root) -PassThru -WindowStyle Hidden
try {
  Start-Sleep -Seconds 2
  $html = & $chrome --headless=new --disable-gpu --virtual-time-budget=($TimeoutSec * 1000) --dump-dom 'http://127.0.0.1:8765' 2>&1
  if (($html -join "`n") -notmatch '<div id="bench-complete">18</div>') { throw "Chrome did not reach the MEAS-02 completion marker: $html" }
  $matches = @($html | Select-String '<pre class="bench-result" id="bench-result-[0-9]+">' | ForEach-Object { $_.ToString() -replace '.*<pre class="bench-result" id="bench-result-[0-9]+">', '' -replace '</pre>.*', '' })
  if ($matches.Count -ne 18) { throw "Expected 18 completed DOM rows, got $($matches.Count)" }
  [IO.File]::WriteAllLines($rawRows, @($csvHeader) + $matches, [Text.UTF8Encoding]::new($false))
  $rows = @(Import-Csv -LiteralPath $rawRows)
  $expected = @('FLIP.I420.V', 'FLIP.NV12.V', 'FLIP.BGRA.V') | ForEach-Object { $scenario = $_; @('1920x1080', '4000x3000') | ForEach-Object { $size = $_; 1..3 | ForEach-Object { "$scenario|$size|$_" } } }
  $actual = @($rows | ForEach-Object { "$($_.scenario_id)|$($_.width)x$($_.height)|$($_.round)" })
  if ($rows.Count -ne 18 -or @($actual | Sort-Object -Unique).Count -ne 18 -or @(Compare-Object $expected $actual).Count -ne 0) { throw 'DOM CSV does not contain the complete MEAS-02 matrix' }
  foreach ($row in $rows) {
    if ($row.platform -ne 'web' -or $row.version -ne 'abi_v1' -or $row.sha -ne $sha -or $row.src_tree_id -ne $tree -or $row.op -ne 'flip' -or $row.params -ne 'direction=V' -or $row.layout -ne 'tight' -or $row.level -ne 'dart' -or $row.status -notin @('OK', 'UNSUPPORTED')) { throw "Invalid Web CSV metadata/status: $($row | ConvertTo-Json -Compress)" }
  }
  [IO.File]::WriteAllLines($OutCsv, @($csvHeader) + $matches, [Text.UTF8Encoding]::new($false))
  Write-Host "Web ABI v1: 18 validated rows -> $OutCsv"
} finally {
  Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $rawRows -Force -ErrorAction SilentlyContinue
}
