<#
.SYNOPSIS
    PERF-01 matrix driver for the native C harness (tool/bench/native, executable yuv_bench.exe).

.DESCRIPTION
    Runs rounds x sizes x scenarios x targets, one yuv_bench process per row, as specified in
    doc/perf/PERF-01-bench-setup.md ("Run environment controls", "Warm-up and repetitions"):

    - Versions are interleaved per row: every target runs a scenario before the next scenario
      starts, so thermal drift hits all targets alike.
    - Each child pins itself to -Affinity and raises itself to high priority (--affinity,
      --priority high) before it builds any input.
    - Watchdog: the calibration call must finish within -TimeoutSec (120 s) after the child
      reports "ready". Once calibrated, the child gets a budget derived from t1 and the
      adaptive plan. A killed child gets a TIMEOUT row, a crashed one an ERROR:crash row,
      both built from the row template the harness printed at start-up.
    - Every row lands in one CSV (-OutCsv). The harness appends its own rows; the driver
      appends only rows the harness could not write itself.

    The default targets are the 0.2.4 baseline and the ABI v1 baseline. For a PERF card pass
    -Targets with a "before" and an "after" ABI v1 build instead.

.EXAMPLE
    $B = "$env:TEMP\yuv_ffi_bench"
    .\tool\bench\run_matrix.ps1 -Exe "$B\bench_build\Release\yuv_bench.exe" `
        -DllV024 "$B\v024\build\Release\yuv_ffi.dll" -DllAbiV1 "$B\abi_v1\build\Release\yuv_ffi.dll" `
        -InputDir "$B\inputs" -OutCsv "$B\results\meas01_windows.csv"

.EXAMPLE
    # PERF card: before/after on ABI v1, one scenario family, one size.
    .\tool\bench\run_matrix.ps1 -Exe $Exe -InputDir "$B\inputs" -OutCsv "$B\results\perf02.csv" `
        -Sizes 1920x1080 -Scenarios 'CVT.*' -Targets @(
            @{ Version = 'abi_v1'; Dll = "$B\before\build\Release\yuv_ffi.dll"; Sha = '<parent sha>'; Tree = '<parent src tree>' },
            @{ Version = 'abi_v1'; Dll = "$B\after\build\Release\yuv_ffi.dll";  Sha = '<card sha>';   Tree = '<card src tree>' })
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Exe,
    [Parameter(Mandatory)] [string] $InputDir,
    [Parameter(Mandatory)] [string] $OutCsv,
    [string] $DllV024,
    [string] $DllAbiV1,
    [hashtable[]] $Targets,
    [string[]] $Sizes = @('1920x1080', '4000x3000'),
    [int[]] $Rounds = @(1, 2, 3),
    [string[]] $Scenarios = @('*'),
    [switch] $IncludeMemcpyRef,
    [string] $ShaV024 = '5f52fd14540a283da91a6d80e1fc7128bba1c796',
    [string] $TreeV024 = 'eba076b4cc9a0d7a686b61edbbb8101da9270356',
    [string] $ShaAbiV1 = '35c516e216fef8d5ed4ef379d38655fc643f738d',
    [string] $TreeAbiV1 = '9029ff28d9834c069f41159d122b36ed6d9d4968',
    [string] $Affinity = '0x4',
    [int] $TimeoutSec = 120,
    [int] $SetupTimeoutSec = 120,
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Must match kCsvHeader in tool/bench/native/bench_main.c.
$CsvHeader = 'platform,machine,round,version,sha,src_tree_id,scenario_id,op,src_fmt,dst_fmt,width,height,params,layout,' +
    'level,status,reason,warmup,n,min_ms,median_ms,p95_or_max_ms,upper_kind,mean_ms,stdev_ms,spread,checksum_sha256,' +
    'raw_ms,started_at,finished_at,compiler,flags,power_plan,affinity'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function ConvertTo-ArgLine([string[]] $Values) {
    $quoted = foreach ($v in $Values) {
        if ($v -eq '' -or $v -match '[\s"]') {
            # CommandLineToArgvW: backslashes before a closing quote must be doubled.
            '"' + (($v -replace '"', '\"') -replace '(\\+)$', '$1$1') + '"'
        } else {
            $v
        }
    }
    $quoted -join ' '
}

function Get-UtcStamp { (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fff'Z'") }

function Add-CsvLine([string] $Line) {
    $dir = Split-Path -Parent $OutCsv
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    if (-not (Test-Path $OutCsv) -or (Get-Item $OutCsv).Length -eq 0) {
        [IO.File]::AppendAllText($OutCsv, $CsvHeader + "`r`n", $Utf8NoBom)
    }
    [IO.File]::AppendAllText($OutCsv, $Line + "`r`n", $Utf8NoBom)
}

function Read-SharedText([string] $Path) {
    # The child still holds the redirect handle; open with ReadWrite sharing so polling never blocks it.
    try {
        $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
    } catch {
        ''
    }
}

# Same adaptive rule as plan_for() in bench_main.c; the extra 60 s covers restore, pre-fill and hashing.
function Get-RunBudgetSec([double] $T1Ms, [int] $Warmup, [int] $N) {
    [Math]::Ceiling(($Warmup + $N) * $T1Ms * 2 / 1000.0) + 60
}

function New-FallbackRow($Target, [string] $Id, [string] $Size, [int] $Round, [string] $Status, [string] $Reason,
                         [string] $Started) {
    $w, $h = $Size -split 'x'
    $cols = New-Object string[] 34
    $cols[0] = 'windows-x64'; $cols[1] = $env:COMPUTERNAME; $cols[2] = "$Round"; $cols[3] = $Target.Version
    $cols[4] = $Target.Sha; $cols[5] = $Target.Tree; $cols[6] = $Id; $cols[10] = $w; $cols[11] = $h
    $cols[13] = 'tight'; $cols[14] = 'c'; $cols[15] = $Status; $cols[16] = $Reason -replace '[,\r\n]', ';'
    $cols[28] = $Started; $cols[29] = Get-UtcStamp; $cols[32] = $script:PowerPlan; $cols[33] = $Affinity
    ($cols | ForEach-Object { if ($null -eq $_) { '' } else { $_ } }) -join ','
}

# --- Inputs and environment --------------------------------------------------------------

$Exe = (Resolve-Path $Exe).Path
$InputDir = $InputDir.TrimEnd('\')
if (-not $Targets) {
    if (-not $DllV024 -or -not $DllAbiV1) { throw 'Pass -DllV024 and -DllAbiV1, or -Targets.' }
    $Targets = @(
        @{ Version = 'v024'; Dll = $DllV024; Sha = $ShaV024; Tree = $TreeV024 },
        @{ Version = 'abi_v1'; Dll = $DllAbiV1; Sha = $ShaAbiV1; Tree = $TreeAbiV1 }
    )
}
if ($IncludeMemcpyRef) { $Targets += @{ Version = 'ref.memcpy'; Dll = ''; Sha = ''; Tree = '' } }
foreach ($t in $Targets) {
    foreach ($k in 'Version', 'Dll', 'Sha', 'Tree') { if (-not $t.ContainsKey($k)) { $t[$k] = '' } }
    if ($t.Version -ne 'ref.memcpy') {
        if (-not $t.Dll -or -not (Test-Path $t.Dll)) { throw "DLL not found for target $($t.Version): '$($t.Dll)'" }
        $t.Dll = (Resolve-Path $t.Dll).Path
    }
}

$script:PowerPlan = ''
$scheme = (& powercfg /getactivescheme) -join ' '
if ($scheme -match '\(([^)]+)\)') { $script:PowerPlan = $Matches[1] }

$matrix = foreach ($line in (& $Exe --list)) {
    $id, $only1080 = $line -split "`t"
    [pscustomobject]@{ Id = $id; Only1080 = ($only1080 -eq '1') }
}
$selected = @($matrix | Where-Object { $id = $_.Id; @($Scenarios | Where-Object { $id -like $_ }).Count -gt 0 })
if ($selected.Count -eq 0) { throw "No scenario matches -Scenarios $($Scenarios -join ', ')" }

$work = Join-Path ([IO.Path]::GetTempPath()) ("yuv_bench_driver_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
$roundsLog = "$OutCsv.rounds.log"

# Create the output directory before the first child runs so that both the harness
# (which appends its own rows) and the rounds log can write without racing on mkdir.
$outDir = Split-Path -Parent $OutCsv
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }

Write-Host "yuv_bench driver: $($selected.Count) scenarios x $($Sizes.Count) sizes x $($Targets.Count) targets x $($Rounds.Count) rounds"
Write-Host "power plan: '$script:PowerPlan', affinity: $Affinity, out: $OutCsv"

# --- One row -----------------------------------------------------------------------------

function Invoke-Row($Target, [string] $Id, [string] $Size, [int] $Round) {
    $argv = @('--version', $Target.Version, '--inputs', $InputDir, '--out', $OutCsv, '--scenario', $Id,
        '--size', $Size, '--round', "$Round", '--sha', $Target.Sha, '--tree', $Target.Tree,
        '--machine', $env:COMPUTERNAME, '--power-plan', $script:PowerPlan, '--priority', 'high')
    if ($Target.Dll) { $argv += @('--dll', $Target.Dll) }
    if ($Affinity) { $argv += @('--affinity', $Affinity) }
    $argLine = ConvertTo-ArgLine $argv

    if ($DryRun) {
        Write-Host "$Exe $argLine"
        return
    }

    $outFile = Join-Path $work 'row.out'
    $errFile = Join-Path $work 'row.err'
    Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
    $started = Get-UtcStamp
    $p = Start-Process -FilePath $Exe -ArgumentList $argLine -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $deadline = (Get-Date).AddSeconds($SetupTimeoutSec)
    $ready = $false
    $calibrated = $false
    $killReason = $null

    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 200
        $err = Read-SharedText $errFile
        if (-not $ready -and $err -match '(?m)^ready') {
            $ready = $true
            $deadline = (Get-Date).AddSeconds($TimeoutSec)
        }
        if (-not $calibrated -and $err -match 'calibrated t1_ms=([0-9.]+) warmup=(\d+) n=(\d+)') {
            $calibrated = $true
            $deadline = (Get-Date).AddSeconds((Get-RunBudgetSec ([double]$Matches[1]) ([int]$Matches[2]) ([int]$Matches[3])))
        }
        if ((Get-Date) -gt $deadline) {
            if (-not $ready) { $killReason = "killed by driver: no 'ready' within $SetupTimeoutSec s (setup)" }
            elseif (-not $calibrated) { $killReason = ">$TimeoutSec s; calibration call did not finish (killed by driver watchdog)" }
            else { $killReason = 'killed by driver: measured runs exceeded the budget derived from t1' }
            try { $p.Kill() } catch { }
            $p.WaitForExit()
            break
        }
    }
    $p.WaitForExit()
    $exitCode = $p.ExitCode

    $row = (Read-SharedText $outFile).Trim()
    if ($row -and -not $killReason) {
        $f = $row -split ','
        $rowStatus = $f[15]
        if ($rowStatus -like 'ERROR:*') {
            Write-Host ("  r{0} {1,-9} {2,-10} {3,-18} {4,-24} {5} {6}" -f $Round, $Size, $Target.Version, $Id, $rowStatus, $f[16])
            return $rowStatus
        }
        Write-Host ("  r{0} {1,-9} {2,-10} {3,-18} {4,-24} median={5} {6}" -f $Round, $Size, $Target.Version, $Id, $f[15], $f[20], $f[16])
        return
    }

    $err = Read-SharedText $errFile
    if ($killReason) {
        $status = if ($calibrated) { 'ERROR:budget' } else { 'TIMEOUT' }
        $reason = $killReason
    } else {
        $status = 'ERROR:crash'
        $reason = ('exit code 0x{0:X8} without a result row' -f $exitCode)
    }
    if ($err -match '(?m)^row-template: (.+)$') {
        $line = $Matches[1].Trim().Replace('@STATUS@', $status).Replace('@REASON@', ($reason -replace '[,\r\n]', ';')).Replace('@FINISHED@', (Get-UtcStamp))
    } else {
        $line = New-FallbackRow $Target $Id $Size $Round $status $reason $started
    }
    Add-CsvLine $line
    Write-Host ("  r{0} {1,-9} {2,-10} {3,-18} {4,-24} {5}" -f $Round, $Size, $Target.Version, $Id, $status, $reason)
}

# --- Matrix ------------------------------------------------------------------------------

$errorRows = 0
try {
    foreach ($round in $Rounds) {
        $roundStart = Get-UtcStamp
        Write-Host "round $round started $roundStart"
        foreach ($size in $Sizes) {
            foreach ($s in $selected) {
                if ($s.Only1080 -and $size -ne '1920x1080') { continue }
                foreach ($t in $Targets) {
                    $result = Invoke-Row $t $s.Id $size $round
                    if ($result -like 'ERROR:*' -or $result -eq 'TIMEOUT') { $errorRows++ }
                }
            }
        }
        $roundEnd = Get-UtcStamp
        Write-Host "round $round finished $roundEnd"
        if (-not $DryRun) {
            [IO.File]::AppendAllText($roundsLog,
                "round=$round start=$roundStart end=$roundEnd power_plan=$script:PowerPlan affinity=$Affinity`r`n", $Utf8NoBom)
        }
    }
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
if ($errorRows -gt 0) {
    Write-Host "yuv_bench driver: $errorRows row(s) with ERROR or TIMEOUT status" -ForegroundColor Red
    exit 1
}
