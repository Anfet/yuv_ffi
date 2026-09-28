<#
.SYNOPSIS
    Builds the public Dart benchmark as a Flutter Windows release app outside the repository.
.EXAMPLE
    .\tool\bench\build_dart_windows.ps1 -Version abi_v1 -SourceRef 35c516e
    .\tool\bench\build_dart_windows.ps1 -Version v024
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('v024', 'abi_v1')] [string] $Version,
    [string] $SourceRef,
    [string] $OutRoot = (Join-Path $env:TEMP 'yuv_ffi_dart_bench')
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if (-not $SourceRef) {
    if ($Version -eq 'v024') { $SourceRef = '0.2.4' }
    else { throw 'Pass -SourceRef with the selected PERF card parent SHA for abi_v1.' }
}
$sourceSha = (& git -C $repo rev-parse "$SourceRef^{commit}").Trim()
if ($LASTEXITCODE -ne 0) { throw "Cannot resolve source ref $SourceRef" }
$srcTreeId = (& git -C $repo rev-parse "${sourceSha}:src").Trim()
if ($LASTEXITCODE -ne 0) { throw "Cannot resolve src tree for $sourceSha" }
$worktree = Join-Path $OutRoot "source_$Version"
$app = Join-Path $OutRoot "app_$Version"
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

if (-not (Test-Path -LiteralPath $worktree)) {
    & git -C $repo worktree add --detach $worktree $sourceSha
    if ($LASTEXITCODE -ne 0) { throw "Cannot create worktree for $sourceSha" }
} else {
    $existing = (& git -C $worktree rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $existing -ne $sourceSha) {
        throw "Existing worktree $worktree is $existing, expected $sourceSha. Choose another -OutRoot."
    }
}
if ((& git -C $worktree status --porcelain)) { throw "Source worktree has changes: $worktree" }

if (-not (Test-Path -LiteralPath (Join-Path $app 'windows'))) {
    & flutter create --platforms=windows --project-name yuv_bench $app
    if ($LASTEXITCODE -ne 0) { throw "Cannot create Flutter app at $app" }
}

$sourcePath = $worktree.Replace('\', '/')
$pubspec = @"
name: yuv_bench
description: Temporary release benchmark app for yuv_ffi
publish_to: none
environment:
  sdk: ^3.10.0
dependencies:
  flutter:
    sdk: flutter
  crypto: ^3.0.6
  yuv_ffi:
    path: '$sourcePath'
flutter:
  uses-material-design: false
"@
[IO.File]::WriteAllText((Join-Path $app 'pubspec.yaml'), $pubspec + "`n", [Text.UTF8Encoding]::new($false))
$dartSource = Join-Path $PSScriptRoot 'dart'
$manifestPath = Join-Path $app 'bench-manifest.json'
Remove-Item -LiteralPath $manifestPath -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $dartSource 'bench_common.dart') -Destination (Join-Path $app 'lib\bench_common.dart') -Force
Copy-Item -LiteralPath (Join-Path $dartSource 'bench_images.dart') -Destination (Join-Path $app 'lib\bench_images.dart') -Force
Copy-Item -LiteralPath (Join-Path $dartSource "bench_$Version.dart") -Destination (Join-Path $app 'lib\main.dart') -Force

Push-Location $app
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    & flutter build windows --release -t lib/main.dart
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }
} finally {
    Pop-Location
}

$flutterInfo = (& flutter --version --machine | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'flutter --version --machine failed' }
$exe = (Join-Path $app 'build\windows\x64\runner\Release\yuv_bench.exe')
$manifest = [ordered]@{
    version = $Version
    sourceSha = $sourceSha
    srcTreeId = $srcTreeId
    executable = [IO.Path]::GetFullPath($exe)
    flutterVersion = $flutterInfo.frameworkVersion
    dartVersion = $flutterInfo.dartSdkVersion
    frameworkRevision = $flutterInfo.frameworkRevision
    engineContentHash = $flutterInfo.engineContentHash
    nativeFlags = 'MSVC Release /MD /O2 /Ob2 /DNDEBUG; no LTO; no AVX'
    benchCommonSha256 = (Get-FileHash -LiteralPath (Join-Path $app 'lib\bench_common.dart') -Algorithm SHA256).Hash
    benchImagesSha256 = (Get-FileHash -LiteralPath (Join-Path $app 'lib\bench_images.dart') -Algorithm SHA256).Hash
    benchMainSha256 = (Get-FileHash -LiteralPath (Join-Path $app 'lib\main.dart') -Algorithm SHA256).Hash
}
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 3) + "`n", [Text.UTF8Encoding]::new($false))

Write-Host "Version: $Version; source SHA: $sourceSha"
Write-Host "App: $app"
Write-Host "Executable: $exe"
Write-Host "Manifest: $manifestPath"
