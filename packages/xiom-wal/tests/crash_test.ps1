#!/usr/bin/env pwsh
# ============================================================================
# XIOM xiom.wal crash/reopen test -- durable WAL critical primitive.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Adapted from ORBITDB scripts/crash_test.ps1 (commit 12405f5) for the
# xiom.wal package surface. Drives tests/probes/probe_wal_crash.xi:
#   1. writer appends N records, then hangs (crash simulation);
#   2. hard-kill the writer process tree once N records are visible;
#   3. append a torn tail ("torn|", no newline) -- crash mid-record;
#   4. reopen: replay the segment, expect exactly N records (torn skipped);
#   5. append one more record (torn-tail healing) and expect N+1;
#   6. truncate smoke: keep lsn >= N-5 -> replay exactly 7
#      (N=20 gives the reference smoke: keep lsn >= 15 -> replay 7).
#
# Toolchain: resolved by dot-sourcing the repo's scripts/xiom.ps1
# (Resolve-XiomToolchain; read-only). Scratch segment + probe logs live under
# %TEMP%\kilo, never in the repo.
#
# Usage: powershell -NoProfile -File tests\crash_test.ps1 [-Events 20] [-TimeoutSec 90]
# Exit:  0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Events = 20,
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = "Stop"

if (-not $env:XIOM_COMPILER -or -not (Test-Path -LiteralPath $env:XIOM_COMPILER)) {
    $env:XIOM_COMPILER = Join-Path $env:LOCALAPPDATA "xiom.new\bin\xiom.exe"
}
# Toolchain resolver: the brief's $PSScriptRoot\..\..\scripts\xiom.ps1
# assumes the package sits directly under the repo root; in this checkout the
# package is at <repo>\packages\xiom-wal, so try one level deeper first and
# keep the brief's path as fallback. Read-only in both cases.
$resolver = ""
$candidates = @(
    (Join-Path $PSScriptRoot "..\..\..\scripts\xiom.ps1"),
    (Join-Path $PSScriptRoot "..\..\scripts\xiom.ps1")
)
foreach ($c in $candidates) {
    $full = [System.IO.Path]::GetFullPath($c)
    if (Test-Path -LiteralPath $full) { $resolver = $full; break }
}
if (-not $resolver) { throw "toolchain resolver not found (tried: $($candidates -join ', '))" }
. $resolver
$tool = Resolve-XiomToolchain
if ($tool.Stdlib) { $env:XIOM_STDLIB = $tool.Stdlib }

$pkgDir = Split-Path -Parent $PSScriptRoot
$probe = Join-Path $PSScriptRoot "probes\probe_wal_crash.xi"
if (-not (Test-Path -LiteralPath $probe)) { throw "probe not found: $probe" }

$scratch = Join-Path $env:TEMP "kilo"
if (-not (Test-Path -LiteralPath $scratch)) { New-Item -ItemType Directory -Path $scratch | Out-Null }
$walFile = Join-Path $scratch "xiom-wal-crash.seg"
if (Test-Path -LiteralPath $walFile) { Remove-Item -LiteralPath $walFile -Force }

$pass = 0; $fail = 0
function Check {
    param([string]$Name, [bool]$Ok)
    if ($Ok) { Write-Host "[PASS] $Name"; $script:pass++ }
    else { Write-Host "[FAIL] $Name"; $script:fail++ }
}

# Runs one probe mode under a watchdog; returns the program's exit code
# (124 on timeout). Cleans this run's a.exe/a.exe.ll scratch from the
# package dir (the probe is compiled with the package dir as cwd).
function Invoke-ProbeMode {
    param(
        [string]$Mode,
        [int]$N = 0,
        [string]$LastKey = "",
        [string]$LastVal = "",
        [string]$From = "",
        [string]$Expect = "",
        [string]$First = "",
        [string]$SkipKey1 = ""
    )
    $env:XIOM_WAL_FILE = $walFile
    $env:XIOM_WAL_MODE = $Mode
    $env:XIOM_WAL_N = "$N"
    if ($LastKey) { $env:XIOM_WAL_LAST_KEY = $LastKey } else { Remove-Item Env:XIOM_WAL_LAST_KEY -ErrorAction SilentlyContinue }
    if ($LastVal) { $env:XIOM_WAL_LAST_VAL = $LastVal } else { Remove-Item Env:XIOM_WAL_LAST_VAL -ErrorAction SilentlyContinue }
    if ($From) { $env:XIOM_WAL_FROM = $From } else { Remove-Item Env:XIOM_WAL_FROM -ErrorAction SilentlyContinue }
    if ($Expect) { $env:XIOM_WAL_EXPECT = $Expect } else { Remove-Item Env:XIOM_WAL_EXPECT -ErrorAction SilentlyContinue }
    if ($First) { $env:XIOM_WAL_FROM = $First }
    if ($SkipKey1) { $env:XIOM_WAL_SKIP_KEY1 = $SkipKey1 } else { Remove-Item Env:XIOM_WAL_SKIP_KEY1 -ErrorAction SilentlyContinue }

    $base = Join-Path $scratch ("wal-probe-" + [guid]::NewGuid().ToString("N"))
    $outFile = "$base.out"
    $errFile = "$base.err"
    $proc = Start-Process -FilePath $tool.Xiom -ArgumentList @("--run", $probe) `
        -WorkingDirectory $pkgDir -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $timedOut = $false
    try {
        $proc | Wait-Process -Timeout $TimeoutSec -ErrorAction Stop
    } catch {
        $timedOut = $true
    }
    if ($timedOut -and -not $proc.HasExited) {
        & taskkill /T /F /PID $proc.Id 2>$null | Out-Null
        Start-Sleep -Milliseconds 300
    }
    $output = ""
    if (Test-Path -LiteralPath $outFile) { $output += (Get-Content -LiteralPath $outFile -Raw) }
    if (Test-Path -LiteralPath $errFile) { $output += (Get-Content -LiteralPath $errFile -Raw) }
    Remove-Item -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $pkgDir "a.exe"), (Join-Path $pkgDir "a.exe.ll") -ErrorAction SilentlyContinue

    foreach ($line in ($output -split "`r?`n")) {
        if ($line.Trim()) { Write-Host "  probe| $($line.Trim())" }
    }
    $programExit = $null
    $codeMatches = [regex]::Matches($output, "exit code:\s*(-?\d+)")
    if ($codeMatches.Count -gt 0) {
        $programExit = [int64]$codeMatches[$codeMatches.Count - 1].Groups[1].Value
    }
    if ($timedOut) { return 124 }
    if ($null -ne $programExit) { return $programExit }
    return $proc.ExitCode
}

# --- phase 1: writer appends Events records, then hangs --------------------
$env:XIOM_WAL_FILE = $walFile
$env:XIOM_WAL_MODE = "write"
$env:XIOM_WAL_N = "$Events"
$writerOut = Join-Path $scratch "wal-writer.out"
$writerErr = Join-Path $scratch "wal-writer.err"
$writer = Start-Process -FilePath $tool.Xiom -ArgumentList @("--run", $probe) `
    -WorkingDirectory $pkgDir -NoNewWindow -PassThru `
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
Remove-Item -LiteralPath $writerOut, $writerErr -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $walFile) {
    Add-Content -LiteralPath $walFile -Value "torn|" -NoNewline
    Write-Host ("crash: killed writer, segment={0} bytes, torn tail appended" -f (Get-Item -LiteralPath $walFile).Length)
} else {
    Write-Host "crash: segment missing; torn tail skipped"
}

# --- phase 3: reopen, prefix must be intact despite the torn tail ----------
$rc = Invoke-ProbeMode -Mode "verify" -N $Events
Check "reopen replays prefix ($Events) with torn tail skipped" ($rc -eq 0)

# --- phase 4: heal + append one more record --------------------------------
$rc = Invoke-ProbeMode -Mode "append1" -N $Events
Check "append after torn tail heals (append1 exit 0)" ($rc -eq 0)

# --- phase 5: N+1 and last-record integrity --------------------------------
$rc = Invoke-ProbeMode -Mode "verify" -N ($Events + 1) -LastKey "9999" -LastVal "99990"
Check "reopen sees $($Events + 1) records incl. healed append" ($rc -eq 0)

# --- phase 6: truncate smoke (keep lsn >= N-5 -> replay 7) -----------------
$from = $Events - 5
$expect = $Events - $from + 2
$rc = Invoke-ProbeMode -Mode "truncate" -From "$from" -Expect "$expect"
Check "truncate keeps lsn >= $from (replay $expect)" ($rc -eq 0)
$rc = Invoke-ProbeMode -Mode "verify" -N $expect -First "$from" -LastKey "9999" -LastVal "99990" -SkipKey1 "1"
Check "post-truncate replay: $expect records, first lsn $from, healed tail intact" ($rc -eq 0)

Write-Host ("crash: pass={0} fail={1}" -f $pass, $fail)
if ($fail -eq 0) {
    if (Test-Path -LiteralPath $walFile) { Remove-Item -LiteralPath $walFile -Force }
    Write-Host "crash: GREEN"
    exit 0
}
Write-Host "crash: RED"
exit 1
