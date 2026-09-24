# Test-only diagnostic runner for YUV-40 (F-010: Web/WASM reference matrix
# abort investigation). Not part of the build/test pipeline; not invoked by
# CI. Exists so every `flutter drive -d web-server --browser-name=chrome`
# attempt against a named
# integration_test target ends in exactly one of two terminal results:
#
#   flutter_exit=<n>   -- the OS-level exit code of the flutter.bat process,
#                          read via Process.ExitCode of a `cmd.exe /c`
#                          child (never $LASTEXITCODE or a pipe/redirect
#                          proxy, and never coerced from a null value: if
#                          ExitCode cannot be read after the process reports
#                          itself exited, the script throws instead of
#                          inventing a third silent outcome).
#   timeout             -- the process did not exit within -TimeoutSeconds and
#                          was killed; no exit code exists for a killed
#                          process, so this is reported as a distinct outcome,
#                          not conflated with any numeric code. May carry a
#                          diagnosed-cause suffix (see below) but is still
#                          the `timeout` outcome, not a third result.
#
# Process isolation: this script starts its own chromedriver and tracks its
# PID ($driverProc). Cleanup ONLY ever stops that PID, the flutter/cmd.exe
# process this run itself launched, and Chrome processes parented by this
# run's own chromedriver PID (WebDriver launches the browser, so Chrome is a
# child of chromedriver, not of the flutter client) -- it never stops
# chromedriver or chrome processes by name/commandline pattern, because that
# could kill an unrelated chromedriver run or browser session on the same
# machine. If -Port is already in use by something this script did not
# start, it refuses to run rather than fighting over the port.
#
# Logs and the one-line result file are written under -OutDir/<RunId>.log*,
# where -OutDir defaults to tool/wasm/out/ (gitignored, but inside the repo
# checkout so a reviewer running this script gets output at a path they can
# find, not in a session-scoped temp directory).
#
# Usage:
#   pwsh -File tool/wasm/yuv40_web_matrix_probe.ps1 `
#     -FlutterExe 'D:\.important\flutter-3.44\flutter\bin\flutter.bat' `
#     -ChromedriverExe 'C:\path\to\chromedriver.exe' `
#     -Target integration_test/yuv40_web_matrix_abort_test.dart `
#     -RunId attempt1 `
#     -TimeoutSeconds 150
#
# Requires the caller to supply a chromedriver binary matching the local
# Chrome install (not vendored in this repo) and a Flutter SDK capable of
# `flutter drive -d web-server --browser-name=chrome`.

param(
    [Parameter(Mandatory = $true)][string]$FlutterExe,
    [Parameter(Mandatory = $true)][string]$ChromedriverExe,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$RunId,
    [string]$OutDir = "",
    [string]$DartDefine = "",
    [int]$Port = 4444,
    [int]$TimeoutSeconds = 150
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$examplePath = Join-Path $repoRoot "example"
if ($OutDir -eq "") {
    $OutDir = Join-Path $PSScriptRoot "out"
}
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}
$LogPath = Join-Path $OutDir "$RunId.log"

function Test-PortInUse {
    param([int]$Port)
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return $null -ne $conns
}

if (Test-PortInUse -Port $Port) {
    throw "Port $Port is already in use by another process. This script only ever stops the chromedriver PID it itself starts, so it refuses to share a port with an existing listener rather than risk killing someone else's session. Pick a different -Port or free this one first."
}

$driverStdout = "$LogPath.chromedriver.stdout.log"
$driverStderr = "$LogPath.chromedriver.stderr.log"
$driverProc = Start-Process -FilePath $ChromedriverExe -ArgumentList "--port=$Port" -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $driverStdout -RedirectStandardError $driverStderr
Start-Sleep -Seconds 2

$result = "unknown"
$flutterExitCode = $null
$flutterProc = $null

try {
    # -v (verbose) is required, not optional: it is the only way flutter
    # drive surfaces the DWDS-layer failure signature (AppConnectionException
    # / "Timer stream not supported on web devices") that this probe exists
    # to catch. Without it the process still hangs the same way, but the
    # log gives no way to tell a DWDS failure apart from a plain slow start.
    # Keep the same transport as the required CI Web gate. `-d chrome` uses a
    # DWDS debug-service subscription to the unsupported `Timer` stream on
    # Flutter 3.44, so it can hang before the integration target executes.
    $argList = @("drive", "--driver=test_driver/integration_test.dart", "--target=$Target", "-d", "web-server", "--browser-name=chrome", "--headless", "-v")
    if ($DartDefine -ne "") {
        $argList += "--dart-define=$DartDefine"
    }

    # Run through `cmd.exe /c` rather than Start-Process -FilePath on the
    # .bat directly: PowerShell's Process class does not reliably surface
    # .ExitCode for a batch file launched that way (observed as ExitCode
    # coming back empty on a run that had, per its own log, already reached
    # "Application finished."). Routing through cmd.exe /c gives a real
    # child process whose exit code is the batch file's own, unambiguously.
    $cmdArgs = @("/c", $FlutterExe) + $argList
    $flutterProc = Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -WorkingDirectory $examplePath `
        -PassThru -WindowStyle Hidden -RedirectStandardOutput $LogPath -RedirectStandardError "$LogPath.stderr.log"

    $exited = $flutterProc.WaitForExit($TimeoutSeconds * 1000)

    if ($exited) {
        # .NET's own documentation for WaitForExit(Int32) warns that after it
        # returns true, a caller that needs to read ExitCode/redirected
        # streams reliably must also call the parameterless WaitForExit() --
        # otherwise ExitCode can still read as unset because the process's
        # internal state (in particular the exit code from the OS) is not
        # guaranteed to be flushed yet. Observed directly: attempt 11 hit
        # this exact race (flutter's own log showed "exiting with code 0",
        # yet ExitCode read back null immediately after WaitForExit(150000)
        # returned true).
        $flutterProc.WaitForExit()
        $flutterExitCode = $flutterProc.ExitCode
        if ($null -eq $flutterExitCode) {
            # This is the one case that must never happen silently: the
            # contract promises exactly two outcomes. If the process reports
            # exited=true after both WaitForExit calls but ExitCode still
            # can't be read, that is a bug in this script's assumptions, not
            # a legitimate third result -- fail loudly instead of inventing
            # "exit_code_unavailable".
            throw "flutter drive process (PID $($flutterProc.Id)) reported exited=true but ExitCode was null even after the parameterless WaitForExit() follow-up. This breaks the two-outcome contract of this script; investigate rather than treating it as a normal result."
        }
        $result = "flutter_exit=$flutterExitCode"
    }
    else {
        Stop-Process -Id $flutterProc.Id -Force -ErrorAction SilentlyContinue
        $result = "timeout"
        # A timeout is a killed process, not a diagnosis. Grep the -v log for
        # the known DWDS failure signature (see 2026-09-22 verbose run: an
        # AppConnectionException at DevHandler._startLocalDebugService,
        # followed by "The stream `Timer` is not supported on web devices"
        # and a "Shutting down Chromium." that never reaches a clean exit)
        # so the summary distinguishes a diagnosed cause from an unexplained
        # hang. This is still the `timeout` outcome, only annotated.
        if (Test-Path $LogPath) {
            $logTail = Get-Content $LogPath -Raw -ErrorAction SilentlyContinue
            if ($logTail -match "AppConnectionException") {
                $result = "timeout (AppConnectionException in DWDS handshake)"
            }
        }
    }
}
finally {
    # Only ever stop the PIDs this run itself started: driverProc (this
    # script's own chromedriver) and, if it exists, the flutter/cmd.exe
    # child tree this run launched. Never a name- or commandline-based sweep
    # of chromedriver.exe / chrome.exe -- that would risk killing an
    # unrelated run on the same machine.
    if ($driverProc -and -not $driverProc.HasExited) {
        Stop-Process -Id $driverProc.Id -Force -ErrorAction SilentlyContinue
    }
    if ($flutterProc -and -not $flutterProc.HasExited) {
        Stop-Process -Id $flutterProc.Id -Force -ErrorAction SilentlyContinue
    }
    # WebDriver launches the browser, not the flutter/cmd.exe client: Chrome
    # is a child of THIS run's own chromedriver process ($driverProc), not of
    # $flutterProc. Stop only Chrome processes parented by this run's own
    # chromedriver PID -- never a name/commandline sweep of chrome.exe, which
    # would risk killing a browser tab or session unrelated to this run.
    if ($driverProc) {
        Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ParentProcessId -eq $driverProc.Id } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
}

$summaryLine = "YUV40_PROBE_RESULT target=$Target result=$result log=$LogPath"
# Written to a separate file, not appended to $LogPath: Start-Process keeps a
# handle open on the redirected stdout file briefly after WaitForExit
# returns, so an immediate Add-Content to the same path can lose a race
# against the OS releasing that handle.
Set-Content -Path "$LogPath.result" -Value $summaryLine
Write-Output $summaryLine

switch -Wildcard ($result) {
    "flutter_exit=*" { exit $flutterExitCode }
    "timeout*" { exit 124 }
}
