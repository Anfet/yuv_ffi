[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$wrapper = (Resolve-Path (Join-Path $PSScriptRoot '../drive.ps1')).Path
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) "yuv-drive-contract-$([guid]::NewGuid())"
$originalPath = $env:PATH
$originalTemp = $env:TEMP
$originalTmp = $env:TMP
$originalLocation = (Get-Location).Path
$mockVariables = @('MOCK_RECORD', 'MOCK_STDOUT', 'MOCK_STDERR', 'MOCK_EXIT')
$originalMock = @{}
foreach ($name in $mockVariables) { $originalMock[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
  New-Item -ItemType Directory -Path "$scratch/bin", "$scratch/logs" | Out-Null
  '@echo off', '@pwsh -NoProfile -File "%~dp0mock.ps1" %*' | Set-Content -LiteralPath "$scratch/bin/flutter.cmd"
  @'
@((Get-Location).Path) + $args | Set-Content -LiteralPath $env:MOCK_RECORD
Get-Content -LiteralPath $env:MOCK_STDOUT
Get-Content -LiteralPath $env:MOCK_STDERR | ForEach-Object { [Console]::Error.WriteLine($_) }
exit [int]$env:MOCK_EXIT
'@ | Set-Content -LiteralPath "$scratch/bin/mock.ps1"
  $env:PATH = "$scratch/bin;$originalPath"
  $env:TEMP = "$scratch/logs"
  $env:TMP = "$scratch/logs"
  $env:MOCK_RECORD = "$scratch/argv"
  $env:MOCK_STDOUT = "$scratch/stdout"
  $env:MOCK_STDERR = "$scratch/stderr"
  $target = 'integration_test/mock target.dart'
  $device = 'mock device'
  $cases = @(
    @('clean', $true, 'All tests passed', '', 0),
    @('exit7', $false, 'All tests passed', '', 7),
    @('missing', $false, 'ordinary output', '', 0),
    @('failed-after', $false, "All tests passed`nSome tests failed", '', 0),
    @('failed-before', $false, "Some tests failed`nAll tests passed", '', 0),
    @('details-after', $false, "All tests passed`nFailure Details:", '', 0),
    @('details-before', $false, "Failure Details:`nAll tests passed", '', 0),
    @('stderr', $false, 'All tests passed', 'Some tests failed', 0),
    @('recovery', $true, "Error is ordinary output`nAll tests passed", '', 0)
  )
  $failures = 0
  foreach ($case in $cases) {
    $case[2] | Set-Content -LiteralPath $env:MOCK_STDOUT
    $case[3] | Set-Content -LiteralPath $env:MOCK_STDERR
    $env:MOCK_EXIT = [string]$case[4]
    $output = & pwsh -NoProfile -File $wrapper $target $device '--dart-define=label=with space' 2>&1
    $actual = $LASTEXITCODE
    $verdict = @($output | Where-Object { "$_" -eq "PASS $target on $device" }).Count -gt 0
    if (($case[1] -and ($actual -ne 0 -or -not $verdict)) -or
        (-not $case[1] -and ($actual -eq 0 -or $verdict))) {
      Write-Host "FAIL $($case[0]): expected success=$($case[1]); actual exit=$actual wrapper PASS=$verdict"
      $failures++
    }
    $expected = @((Join-Path $repositoryRoot 'example'), 'drive', '--driver=test_driver/integration_test.dart', "--target=$target", '-d', $device, '--dart-define=label=with space')
    $recorded = @(Get-Content -LiteralPath $env:MOCK_RECORD)
    if (($expected -join "`n") -ne ($recorded -join "`n") -or @(Get-ChildItem -LiteralPath "$scratch/logs" -Force).Count -ne 0 -or (Get-Location).Path -ne $originalLocation) {
      Write-Host "FAIL $($case[0]): argv/cwd mismatch or temporary log leaked"
      $failures++
    }
  }
  if ($failures -gt 0) { throw "drive_contract PowerShell: $failures failures / $($cases.Count) cases" }
  Write-Output "drive_contract PowerShell: $($cases.Count) cases passed"
} finally {
  $env:PATH = $originalPath
  $env:TEMP = $originalTemp
  $env:TMP = $originalTmp
  foreach ($name in $mockVariables) { [Environment]::SetEnvironmentVariable($name, $originalMock[$name]) }
  Remove-Item -LiteralPath $scratch -Recurse -Force
}

