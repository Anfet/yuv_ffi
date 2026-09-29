Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_common.ps1')

$repositoryRoot = Get-CiRepositoryRoot
if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot 'pubspec.yaml') -PathType Leaf)) {
  throw "Repository root does not contain pubspec.yaml: $repositoryRoot"
}

$temporaryDirectory = Get-CiTemporaryDirectory
if (-not (Test-Path -LiteralPath $temporaryDirectory -PathType Container)) {
  throw "Temporary directory does not exist: $temporaryDirectory"
}

$flutterRoot = Get-CiFlutterRoot
if (-not (Test-Path -LiteralPath $flutterRoot -PathType Container)) {
  throw "Flutter root does not exist: $flutterRoot"
}

$driveScript = Join-Path $PSScriptRoot 'drive.ps1'
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
  $driveScript,
  [ref] $null,
  [ref] $parseErrors
)
if ($parseErrors.Count -ne 0) {
  throw "PowerShell parser rejected ${driveScript}: $($parseErrors.Message -join '; ')"
}

Write-Output 'CI helper smoke passed.'
