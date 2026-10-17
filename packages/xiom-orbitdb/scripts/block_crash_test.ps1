#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB -- byte-page block store crash harness (M1.2 S2).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Drives tests/probes/probe_block_store.xi (writer/verify modes) through the
# S2 kill matrix. Per state: writer reaches a deterministic quiescent state,
# writes a `.ready` marker and hangs; the harness hard-kills it, appends one
# torn tail block (4096 garbage bytes) to the page area, reopens and checks:
#   pages2    -- half of the next generation appended, uncommitted -> hidden
#   full2     -- whole next generation appended, uncommitted   -> hidden
#   midheader -- inactive header slot torn after a real commit -> fallback ok
#   compacted -- full compaction (temp+rename) done before the hang
# Every verify then appends + commits one recovery page and reopens.
#
# Usage: .\scripts\block_crash_test.ps1 [-Pages 60] [-Batch 10] [-TimeoutSec 180]
# Exit:  0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Pages = 60,
    [int]$Batch = 10,
    [string[]]$KillAts = @("pages2", "full2", "midheader", "compacted"),
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

if (-not $env:XIOM_COMPILER -or -not (Test-Path -LiteralPath $env:XIOM_COMPILER)) {
    . (Join-Path $PSScriptRoot "dev-env.ps1")
    if (-not $env:XIOM_COMPILER) { throw "XIOM_COMPILER not resolved" }
}

$probe = Join-Path $repoRoot "tests\probes\probe_block_store.xi"
$db = Join-Path $logDir "block-crash.db"
$ready = "$db.ready"
$pass = 0; $fail = 0
function Check {
    param([string]$Name, [bool]$Ok)
    if ($Ok) { Write-Host "[PASS] $Name"; $script:pass++ }
    else { Write-Host "[FAIL] $Name"; $script:fail++ }
}

$env:ORBITDB_BLOCK_DB = $db
$env:ORBITDB_BLOCK_N = "$Pages"
$env:ORBITDB_BLOCK_BATCH = "$Batch"

foreach ($killAt in $KillAts) {
    Remove-Item -LiteralPath $db, "$db.tmp", $ready -Force -ErrorAction SilentlyContinue
    $env:ORBITDB_BLOCK_KILL_AT = $killAt
    $env:ORBITDB_BLOCK_MODE = "writer"
    $wout = Join-Path $logDir "block-writer-$killAt.out"
    $werr = Join-Path $logDir "block-writer-$killAt.err"
    $writer = Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("--run", $probe, "-o", (Join-Path $logDir "block-writer-$killAt-$PID.bin.exe")) `
        -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
        -RedirectStandardOutput $wout -RedirectStandardError $werr

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $reached = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $ready) { $reached = $true; break }
        if ($writer.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    Check "[$killAt] writer reached the target state" $reached

    if (-not $writer.HasExited) {
        try { & taskkill /T /F /PID $writer.Id 2>$null | Out-Null } catch { }
        $writer.WaitForExit(10000) | Out-Null
    }
    Start-Sleep -Milliseconds 300

    # Torn tail: one garbage block in the page area.
    $gar = New-Object byte[] 4096
    for ($i = 0; $i -lt $gar.Length; $i++) { $gar[$i] = 0x5A }
    $fs = [System.IO.File]::Open($db, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
    $fs.Write($gar, 0, $gar.Length)
    $fs.Close()

    $env:ORBITDB_BLOCK_MODE = "verify"
    $vout = Join-Path $logDir "block-verify-$killAt.out"
    $verr = Join-Path $logDir "block-verify-$killAt.err"
    $v = Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("--run", $probe, "-o", (Join-Path $logDir "block-verify-$killAt-$PID.bin.exe")) `
        -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
        -RedirectStandardOutput $vout -RedirectStandardError $verr
    $timedOut = $false
    try { $v | Wait-Process -Timeout $TimeoutSec -ErrorAction Stop }
    catch { $timedOut = $true }
    if ($timedOut -and -not $v.HasExited) {
        & taskkill /T /F /PID $v.Id 2>$null | Out-Null
        Start-Sleep -Milliseconds 500
    }
    $text = if (Test-Path -LiteralPath $vout) { Get-Content -LiteralPath $vout -Raw } else { "" }
    if ($null -eq $text) { $text = "" }
    $rc = if ($timedOut) { 124 } else { $v.ExitCode }
    $m = [regex]::Matches($text, "exit code:\s*(-?\d+)")
    if ($m.Count -gt 0) { $rc = [int64]$m[$m.Count - 1].Groups[1].Value }
    Check "[$killAt] verify green (committed view + recovery append)" ($rc -eq 0 -and $text.Contains("verify: GREEN"))
}

Write-Host ("block-crash: pass={0} fail={1}" -f $pass, $fail)
if ($fail -eq 0) { Write-Host "block-crash: GREEN"; exit 0 }
Write-Host "block-crash: RED"
exit 1
