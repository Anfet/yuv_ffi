Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CiRepositoryRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-CiTemporaryDirectory {
  if (-not [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    return $env:RUNNER_TEMP
  }

  return [System.IO.Path]::GetTempPath()
}

function Get-CiFlutterRoot {
  if (-not [string]::IsNullOrWhiteSpace($env:FLUTTER_ROOT)) {
    return $env:FLUTTER_ROOT
  }

  $flutter = Get-Command flutter -ErrorAction Stop
  return (Split-Path -Parent (Split-Path -Parent $flutter.Source))
}

function Invoke-CiNativeCommand {
  param(
    [Parameter(Mandatory)]
    [string] $FilePath,

    [Parameter(ValueFromRemainingArguments)]
    [string[]] $Arguments
  )

  $timer = [System.Diagnostics.Stopwatch]::StartNew()
  $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { $_.ToString() })
  $exitCode = $LASTEXITCODE
  $timer.Stop()
  $command = (@($FilePath) + @($Arguments)) -join ' '
  if ($env:YUV_CI_VERBOSE -eq '1') {
    $output | Write-Output
  }
  if ($exitCode -eq 0) {
    Write-Output ("ok {0} ({1:N2} s)" -f $command, $timer.Elapsed.TotalSeconds)
    return
  }

  Write-Output "$command failed with exit code $exitCode"
  $output | Select-Object -Last 80 | Write-Output
  throw "$FilePath failed with exit code $exitCode"
}

function Invoke-CiFlutterTest {
  param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $Arguments
  )

  & flutter test --reporter json @Arguments | & dart (Join-Path $PSScriptRoot 'test_report.dart')
  if ($LASTEXITCODE -ne 0) {
    throw "flutter test failed with exit code $LASTEXITCODE"
  }
}

function New-CiNativeBuild {
  param(
    [Parameter(Mandatory)]
    [string] $Name,

    [Parameter(Mandatory)]
    [string] $LibraryName,

    [string[]] $CmakeArguments = @()
  )

  $repositoryRoot = Get-CiRepositoryRoot
  $buildDirectory = Join-Path (Get-CiTemporaryDirectory) $Name
  $configureArguments = @('-S', (Join-Path $repositoryRoot 'src'), '-B', $buildDirectory, '-DCMAKE_BUILD_TYPE=Release')
  if ($IsWindows) {
    $configureArguments += @('-A', 'x64')
  }
  $configureArguments += $CmakeArguments

  Invoke-CiNativeCommand cmake @configureArguments
  Invoke-CiNativeCommand cmake '--build', $buildDirectory, '--config', 'Release', '--parallel'

  $libraryPath = if ($IsWindows) {
    Join-Path $buildDirectory (Join-Path 'Release' $LibraryName)
  } else {
    Join-Path $buildDirectory $LibraryName
  }
  if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
    throw "Native library was not produced: $libraryPath"
  }

  return (Split-Path -Parent $libraryPath)
}

function Add-CiPath {
  param(
    [Parameter(Mandatory)]
    [string] $Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Directory does not exist: $Path"
  }

  if ($env:GITHUB_PATH) {
    $Path | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
  }
  $env:PATH = "$Path$([System.IO.Path]::PathSeparator)$env:PATH"
}
