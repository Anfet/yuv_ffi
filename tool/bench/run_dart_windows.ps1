<#
.SYNOPSIS
    Interleaves public Dart AOT benchmark rows for one selected operation.
.EXAMPLE
    .\tool\bench\run_dart_windows.ps1 -ExeV024 $oldExe -ExeAbiV1 $newExe `
        -ScenarioIds FLIP.I420.V,FLIP.NV12.V,FLIP.BGRA.V -OutCsv $csv `
        -ShaAbiV1 $parentSha -TreeAbiV1 $parentSrcTree
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ExeV024,
    [Parameter(Mandatory)] [string] $ExeAbiV1,
    [Parameter(Mandatory)] [string[]] $ScenarioIds,
    [Parameter(Mandatory)] [string] $OutCsv,
    [Parameter(Mandatory)] [string] $ShaAbiV1,
    [Parameter(Mandatory)] [string] $TreeAbiV1,
    [string] $ShaV024 = '5f52fd14540a283da91a6d80e1fc7128bba1c796',
    [string] $TreeV024 = 'eba076b4cc9a0d7a686b61edbbb8101da9270356',
    [string[]] $Sizes = @('1920x1080'),
    [int[]] $Rounds = @(1),
    [string] $Affinity = '0x4',
    [int] $SetupTimeoutSec = 120,
    [int] $TimeoutSec = 120
)

$ErrorActionPreference = 'Stop'
$csvHeader = 'platform,machine,round,version,sha,src_tree_id,scenario_id,op,src_fmt,dst_fmt,width,height,params,layout,level,status,reason,warmup,n,min_ms,median_ms,p95_or_max_ms,upper_kind,mean_ms,stdev_ms,spread,checksum_sha256,raw_ms,started_at,finished_at,compiler,flags,power_plan,affinity'

function Read-SharedText([string] $Path) {
    try {
        $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try { (New-Object IO.StreamReader($stream)).ReadToEnd() } finally { $stream.Dispose() }
    } catch { '' }
}

function Add-FallbackRow($Target, [string] $Scenario, [string] $Size, [int] $Round,
                         [string] $Status, [string] $Reason, [string] $Started) {
    $width, $height = $Size -split 'x'
    $parts = $Scenario -split '\.'
    $columns = New-Object string[] 34
    $columns[0] = 'windows'; $columns[1] = $env:COMPUTERNAME; $columns[2] = "$Round"
    $columns[3] = $Target.Version; $columns[4] = $Target.Sha; $columns[5] = $Target.Tree
    $columns[6] = $Scenario; $columns[7] = $parts[0].ToLowerInvariant()
    $columns[8] = if ($parts.Count -gt 1) { $parts[1].ToLowerInvariant() } else { '' }
    $columns[9] = if ($parts[0] -eq 'CVT' -and $parts.Count -gt 2) { $parts[2].ToLowerInvariant() } else { $columns[8] }
    $columns[10] = $width; $columns[11] = $height; $columns[13] = 'tight'; $columns[14] = 'dart'
    $columns[15] = $Status; $columns[16] = $Reason -replace '[,"\r\n]', ';'
    $columns[28] = $Started; $columns[29] = [DateTime]::UtcNow.ToString('o')
    $columns[30] = $Target.Compiler; $columns[31] = $Target.Flags; $columns[32] = $powerGuid
    $columns[33] = $Affinity
    if (-not (Test-Path -LiteralPath $OutCsv)) {
        [IO.File]::AppendAllText($OutCsv, "$csvHeader`r`n")
    }
    [IO.File]::AppendAllText($OutCsv, (($columns | ForEach-Object { if ($null -eq $_) { '' } else { $_ } }) -join ',') + "`r`n")
}

if (Test-Path -LiteralPath $OutCsv) { throw "Use a new OutCsv path; already exists: $OutCsv" }
foreach ($exe in @($ExeV024, $ExeAbiV1)) {
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing executable: $exe" }
}
function Read-BenchManifest([string] $Exe, [string] $Version, [string] $Sha, [string] $Tree) {
    $resolvedExe = (Resolve-Path -LiteralPath $Exe).Path
    $app = Split-Path -Parent $resolvedExe
    for ($i = 0; $i -lt 5; $i++) { $app = Split-Path -Parent $app }
    $manifestPath = Join-Path $app 'bench-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing build manifest: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.version -ne $Version -or $manifest.sourceSha -ne $Sha -or
        $manifest.srcTreeId -ne $Tree -or $manifest.executable -ne $resolvedExe) {
        throw "Build manifest does not match requested $Version executable, SHA or src tree: $manifestPath"
    }
    foreach ($part in @('benchCommon','benchImages','benchMain')) {
        $source = switch ($part) {
            'benchCommon' { 'bench_common.dart' }
            'benchImages' { 'bench_images.dart' }
            'benchMain' { "bench_$Version.dart" }
        }
        $actual = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "dart\$source") -Algorithm SHA256).Hash
        if ($actual -ne $manifest."${part}Sha256") {
            throw "Benchmark source changed since build: $source; rebuild $Version"
        }
    }
    return $manifest
}
$outDir = Split-Path -Parent $OutCsv
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$mask = [Convert]::ToInt64($Affinity.Replace('0x', ''), 16)
$powerPlan = ((& powercfg /getactivescheme) -join ' ')
$powerGuid = if ($powerPlan -match '[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}') { $Matches[0] } else { 'unknown' }
$manifestV024 = Read-BenchManifest $ExeV024 'v024' $ShaV024 $TreeV024
$manifestAbiV1 = Read-BenchManifest $ExeAbiV1 'abi_v1' $ShaAbiV1 $TreeAbiV1
$targets = @(
    @{ Version = 'v024'; Exe = $ExeV024; Sha = $ShaV024; Tree = $TreeV024;
       Compiler = "Flutter-$($manifestV024.flutterVersion)_Dart-$($manifestV024.dartVersion)_engine-$($manifestV024.engineContentHash.Substring(0, 8))";
       Flags = 'AOT+MSVC-/MD-/O2-/Ob2-/DNDEBUG' },
    @{ Version = 'abi_v1'; Exe = $ExeAbiV1; Sha = $ShaAbiV1; Tree = $TreeAbiV1;
       Compiler = "Flutter-$($manifestAbiV1.flutterVersion)_Dart-$($manifestAbiV1.dartVersion)_engine-$($manifestAbiV1.engineContentHash.Substring(0, 8))";
       Flags = 'AOT+MSVC-/MD-/O2-/Ob2-/DNDEBUG' }
)
$log = "$OutCsv.rounds.log"
$failures = 0
foreach ($round in $Rounds) {
    $roundStart = [DateTime]::UtcNow.ToString('o')
    foreach ($size in $Sizes) {
        foreach ($scenario in $ScenarioIds) {
            if ($scenario -like '*.R256' -and $size -ne '1920x1080') { continue }
            foreach ($target in $targets) {
                $before = if (Test-Path -LiteralPath $OutCsv) { (Get-Content -LiteralPath $OutCsv).Count } else { 0 }
                $stdout = "$OutCsv.stdout.tmp"
                $stderr = "$OutCsv.stderr.tmp"
                $arguments = @(
                    '--scenario', $scenario, '--size', $size, '--round', "$round",
                    '--out', $OutCsv, '--sha', $target.Sha, '--tree', $target.Tree,
                    '--power-plan', $powerGuid, '--affinity', $Affinity,
                    '--compiler', $target.Compiler, '--flags', $target.Flags
                )
                $started = [DateTime]::UtcNow.ToString('o')
                $process = Start-Process -FilePath $target.Exe -ArgumentList $arguments -PassThru `
                    -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
                try {
                    $process.ProcessorAffinity = [IntPtr]$mask
                    $process.PriorityClass = 'High'
                    $deadline = (Get-Date).AddSeconds($SetupTimeoutSec)
                    $ready = $false
                    $calibrated = $false
                    $killReason = $null
                    while (-not $process.HasExited) {
                        Start-Sleep -Milliseconds 200
                        $progress = Read-SharedText $stderr
                        if (-not $ready -and $progress -match '(?m)^ready') {
                            $ready = $true
                            $deadline = (Get-Date).AddSeconds($TimeoutSec)
                        }
                        if (-not $calibrated -and $progress -match 'calibrated t1_ms=([0-9.]+) warmup=(\d+) n=(\d+)') {
                            $calibrated = $true
                            $budget = [Math]::Ceiling((([int]$Matches[2]) + ([int]$Matches[3])) *
                                ([double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)) * 2 / 1000.0) + 60
                            $deadline = (Get-Date).AddSeconds($budget)
                        }
                        if ((Get-Date) -gt $deadline -and -not $process.HasExited) {
                            if (-not $ready) { $killReason = "setup exceeded $SetupTimeoutSec s" }
                            elseif (-not $calibrated) { $killReason = "calibration exceeded $TimeoutSec s" }
                            else { $killReason = 'measured runs exceeded adaptive budget' }
                            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                            break
                        }
                    }
                    $process.WaitForExit()
                    $process.Refresh()
                    $after = if (Test-Path -LiteralPath $OutCsv) { (Get-Content -LiteralPath $OutCsv).Count } else { 0 }
                    if ($after -eq $before) {
                        if ($killReason) {
                            $status = if ($calibrated) { 'ERROR:budget' } else { 'TIMEOUT' }
                            $reason = $killReason
                        } else {
                            $status = if ($ready) { 'ERROR:crash' } else { 'ERROR:setup' }
                            $reason = "exit code $($process.ExitCode) without a result row; $(Read-SharedText $stderr)"
                        }
                        Add-FallbackRow $target $scenario $size $round $status $reason $started
                    }
                    $after = if (Test-Path -LiteralPath $OutCsv) { (Get-Content -LiteralPath $OutCsv).Count } else { 0 }
                    if ($after -ne $before + $(if ($before -eq 0) { 2 } else { 1 })) {
                        throw "Expected one appended row for $scenario $size $($target.Version); CSV line count $before -> $after. $(Read-SharedText $stderr)"
                    }
                    $row = Import-Csv -LiteralPath $OutCsv | Select-Object -Last 1
                    if ($row.scenario_id -ne $scenario -or $row.version -ne $target.Version -or $row.round -ne "$round" -or $row.sha -ne $target.Sha) {
                        throw "CSV metadata mismatch for $scenario $size $($target.Version)"
                    }
                    if ($killReason -or $process.ExitCode -ne 0 -or $row.status -notin @('OK', 'N/A', 'UNSUPPORTED')) { $failures++ }
                    Write-Host "$scenario $size $($target.Version) round=$round status=$($row.status) median_ms=$($row.median_ms)"
                } finally {
                    Remove-Item -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue
                }
            }
        }
    }
    Add-Content -LiteralPath $log -Value "$round,$roundStart,$([DateTime]::UtcNow.ToString('o'))"
}
if ($failures -gt 0) { throw "$failures benchmark row(s) failed; inspect $OutCsv" }
Write-Host "Rows written to $OutCsv"
