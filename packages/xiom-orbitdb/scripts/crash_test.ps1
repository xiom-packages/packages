#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB crash/reopen test -- durable WAL critical primitive.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Drives tests\probes\probe_wal_file.xi:
#   1. writer appends N records, then hangs (crash simulation);
#   2. hard-kill the writer process tree once N records are visible;
#   3. append a torn tail ("torn|", no newline) -- crash mid-record;
#   4. reopen: replay the segment, expect exactly N records (torn skipped);
#   5. append one more record (torn-tail healing) and expect N+1.
#
# Usage: .\scripts\crash_test.ps1 [-Events 20] [-TimeoutSec 90]
# Exit:  0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Events = 20,
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

if (-not $env:XIOM_COMPILER -or -not (Test-Path -LiteralPath $env:XIOM_COMPILER)) {
    . (Join-Path $PSScriptRoot "dev-env.ps1")
    if (-not $env:XIOM_COMPILER) { throw "XIOM_COMPILER not resolved" }
}

$probe = Join-Path $repoRoot "tests\probes\probe_wal_file.xi"
$walFile = Join-Path $logDir "crash-wal.seg"
if (Test-Path -LiteralPath $walFile) { Remove-Item -LiteralPath $walFile -Force }

$pass = 0; $fail = 0
function Check {
    param([string]$Name, [bool]$Ok)
    if ($Ok) { Write-Host "[PASS] $Name"; $script:pass++ }
    else { Write-Host "[FAIL] $Name"; $script:fail++ }
}

function Invoke-ProbeMode {
    param([string]$Mode, [int]$N, [string]$LastKey = "", [string]$LastVal = "")
    $env:ORBITDB_WAL_FILE = $walFile
    $env:ORBITDB_WAL_MODE = $Mode
    $env:ORBITDB_WAL_N = "$N"
    if ($LastKey) { $env:ORBITDB_WAL_LAST_KEY = $LastKey } else { Remove-Item Env:ORBITDB_WAL_LAST_KEY -ErrorAction SilentlyContinue }
    if ($LastVal) { $env:ORBITDB_WAL_LAST_VAL = $LastVal } else { Remove-Item Env:ORBITDB_WAL_LAST_VAL -ErrorAction SilentlyContinue }
    & (Join-Path $PSScriptRoot "run.ps1") $probe -TimeoutSec 180 -Quiet | Out-Null
    return $LASTEXITCODE
}

# --- phase 1: writer appends Events records, then hangs --------------------
$env:ORBITDB_WAL_FILE = $walFile
$env:ORBITDB_WAL_MODE = "write"
$env:ORBITDB_WAL_N = "$Events"
$writerOut = Join-Path $logDir "crash-writer.out"
$writerErr = Join-Path $logDir "crash-writer.err"
$writer = Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("--run", $probe, "-o", (Join-Path $logDir "crash-writer-$PID.bin.exe")) `
    -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
    -RedirectStandardOutput $writerOut -RedirectStandardError $writerErr

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$observed = 0
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $walFile) {
        $observed = @(Get-Content -LiteralPath $walFile -ErrorAction SilentlyContinue).Count
        if ($observed -ge $Events) { break }
    }
    if ($writer.HasExited) { break }
    Start-Sleep -Milliseconds 300
}
Check "writer wrote $Events records (observed=$observed)" ($observed -ge $Events)

# --- phase 2: hard-kill + torn tail ----------------------------------------
if (-not $writer.HasExited) {
    try { & taskkill /T /F /PID $writer.Id | Out-Null } catch { }
    $writer.WaitForExit(10000) | Out-Null
}
Add-Content -LiteralPath $walFile -Value "torn|" -NoNewline
Write-Host ("crash: killed writer, segment={0} bytes, torn tail appended" -f (Get-Item -LiteralPath $walFile).Length)

# --- phase 3: reopen, prefix must be intact despite the torn tail ----------
$rc = Invoke-ProbeMode -Mode "verify" -N $Events
Check "reopen replays prefix ($Events) with torn tail skipped" ($rc -eq 0)

# --- phase 4: heal + append one more record --------------------------------
$rc = Invoke-ProbeMode -Mode "append1" -N $Events
Check "append after torn tail heals (append1 exit 0)" ($rc -eq 0)

# --- phase 5: N+1 and last-record integrity --------------------------------
$rc = Invoke-ProbeMode -Mode "verify" -N ($Events + 1) -LastKey "9999" -LastVal "99990"
Check "reopen sees $($Events + 1) records incl. healed append" ($rc -eq 0)

Write-Host ("crash: pass={0} fail={1}" -f $pass, $fail)
if ($fail -eq 0) { Write-Host "crash: GREEN"; exit 0 }
Write-Host "crash: RED"
exit 1
