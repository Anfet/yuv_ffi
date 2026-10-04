Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_common.ps1')

$repositoryRoot = Get-CiRepositoryRoot
$flutterVersion = $env:FLUTTER_VERSION
if ($flutterVersion -ne '3.44.9') {
  throw "FLUTTER_VERSION must be 3.44.9; got '$flutterVersion'"
}

$installDirectory = Join-Path (Get-CiTemporaryDirectory) "yuv-ffi-flutter-$flutterVersion"
$flutterRoot = Join-Path $installDirectory 'flutter'
$flutterExecutable = Join-Path $flutterRoot 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutterExecutable -PathType Leaf)) {
  try {
    $availableRoot = Get-CiFlutterRoot
    $availableExecutable = Join-Path $availableRoot 'bin\flutter.bat'
    if (Test-Path -LiteralPath $availableExecutable -PathType Leaf) {
      $availableVersion = (& $availableExecutable --version 2>&1 | Out-String)
      if ($LASTEXITCODE -eq 0 -and $availableVersion -match "Flutter $([regex]::Escape($flutterVersion)) ") {
        $flutterRoot = $availableRoot
        $flutterExecutable = $availableExecutable
      }
    }
  } catch {
    # Install the pinned SDK when no usable Flutter SDK is already on PATH.
  }
}

if (-not (Test-Path -LiteralPath $flutterExecutable -PathType Leaf)) {
  New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
  $archivePath = Join-Path $installDirectory "flutter_windows_${flutterVersion}-stable.zip"
  $archiveUri = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_${flutterVersion}-stable.zip"
  Invoke-WebRequest -Uri $archiveUri -OutFile $archivePath -TimeoutSec 600 -MaximumRetryCount 3 -RetryIntervalSec 1
  Expand-Archive -LiteralPath $archivePath -DestinationPath $installDirectory -Force
  Remove-Item -LiteralPath $archivePath -Force
}

if (-not (Test-Path -LiteralPath $flutterExecutable -PathType Leaf)) {
  throw "Flutter $flutterVersion was not installed in $flutterRoot"
}

$env:FLUTTER_ROOT = $flutterRoot
$env:PATH = "$(Join-Path $flutterRoot 'bin')$([System.IO.Path]::PathSeparator)$env:PATH"
$flutterVersionOutput = (& $flutterExecutable --version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $flutterVersionOutput -notmatch "Flutter $([regex]::Escape($flutterVersion)) ") {
  throw "Expected Flutter $flutterVersion, got:`n$flutterVersionOutput"
}
Write-Host "Using Flutter $flutterVersion"

Push-Location (Join-Path $repositoryRoot 'example')
try {
  Invoke-CiNativeCommand $flutterExecutable pub get
  Invoke-CiNativeCommand $flutterExecutable analyze
  Invoke-CiNativeCommand $flutterExecutable build web
} finally {
  Pop-Location
}
