#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB <-> XVECTOR hybrid crash/recovery test (hard kill both stores).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Drives tests/hybrid/probe_hybrid.xi (source-level composition; both src
# trees are source roots via tests/hybrid/xiom.toml):
#   1. writer: ingest N rows (transactions, mid checkpoint) + N-SKIP
#      embeddings, bump LAG row versions without re-embedding, persist the
#      vector WAL, then hang.
#   2. the harness hard-kills the process and appends a torn tail to the row
#      WAL (the vector WAL stays a complete checkpoint).
#   3. verify: reopen both stores (row snapshot + WAL replay, vector WAL
#      load + recover), run the consumer repair pass, and require 100% join
#      integrity; a second verify must find nothing to repair (idempotent).
#
# Usage: .\scripts\hybrid_crash_test.ps1 [-Keys 1000] [-TimeoutSec 180]
# Exit:  0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Keys = 1000,
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

$probe = Join-Path $repoRoot "tests\hybrid\probe_hybrid.xi"
$rowsFile = Join-Path $logDir "hybrid-crash.db"
$vecFile = Join-Path $logDir "hybrid-crash.wal"
Remove-Item -LiteralPath $rowsFile, "$rowsFile.snap", $vecFile, "$vecFile.tmp" -Force -ErrorAction SilentlyContinue

# Fixed scenario knobs (deterministic evidence; see the probe header).
$env:ORBITDB_HYBRID_ROWS = $rowsFile
$env:ORBITDB_HYBRID_VEC = $vecFile
$env:ORBITDB_HYBRID_N = "$Keys"
$env:ORBITDB_HYBRID_DIM = "8"
$env:ORBITDB_HYBRID_SKIP = "10"
$env:ORBITDB_HYBRID_LAG = "3"
$env:ORBITDB_HYBRID_CHUNK = "200"

$pass = 0; $fail = 0
function Check {
    param([string]$Name, [bool]$Ok)
    if ($Ok) { Write-Host "[PASS] $Name"; $script:pass++ }
    else { Write-Host "[FAIL] $Name"; $script:fail++ }
}

# Run the probe in one mode, capture stdout to probe-logs, and return
# @{ rc; text } trusting the "exit code:" line (run.ps1 rule).
function Invoke-Probe {
    param([string]$Mode, [string]$OutName)
    $env:ORBITDB_HYBRID_MODE = $Mode
    $outFile = Join-Path $logDir "$OutName.out"
    $errFile = Join-Path $logDir "$OutName.err"
    $binFile = Join-Path $logDir "$OutName-$PID.bin.exe"
    $proc = Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("--run", $probe, "-o", $binFile) `
        -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $timedOut = $false
    try { $proc | Wait-Process -Timeout $TimeoutSec -ErrorAction Stop }
    catch { $timedOut = $true }
    if ($timedOut -and -not $proc.HasExited) {
        & taskkill /T /F /PID $proc.Id 2>$null | Out-Null
        Start-Sleep -Milliseconds 500
    }
    $text = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw } else { "" }
    if ($null -eq $text) { $text = "" }
    $rc = $proc.ExitCode
    $m = [regex]::Matches($text, "exit code:\s*(-?\d+)")
    if ($m.Count -gt 0) { $rc = [int64]$m[$m.Count - 1].Groups[1].Value }
    if ($timedOut) { $rc = 124 }
    return @{ rc = $rc; text = $text }
}

# --- phase 1: writer ingests + persists + hangs -----------------------------
$env:ORBITDB_HYBRID_MODE = "writer"
$wout = Join-Path $logDir "hybrid-writer.out"
$werr = Join-Path $logDir "hybrid-writer.err"
$writer = Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("--run", $probe, "-o", (Join-Path $logDir "hybrid-writer-$PID.bin.exe")) `
    -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
    -RedirectStandardOutput $wout -RedirectStandardError $werr

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$observed = -1
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $vecFile) {
        $observed = (Get-Item -LiteralPath $vecFile).Length
        if ($observed -gt 0) { break }
    }
    if ($writer.HasExited) { break }
    Start-Sleep -Milliseconds 300
}
Check "writer reached ready point (vector WAL persisted, bytes=$observed)" ($observed -gt 0)

# --- phase 2: hard-kill + torn row tail -------------------------------------
if (-not $writer.HasExited) {
    try { & taskkill /T /F /PID $writer.Id 2>$null | Out-Null } catch { }
    $writer.WaitForExit(10000) | Out-Null
}
Start-Sleep -Milliseconds 300
if (Test-Path -LiteralPath $rowsFile) {
    Add-Content -LiteralPath $rowsFile -Value "torn|" -NoNewline
}
$rowBytes = -1
if (Test-Path -LiteralPath $rowsFile) { $rowBytes = (Get-Item -LiteralPath $rowsFile).Length }
Write-Host ("crash: killed writer, row segment={0} bytes, vector WAL={1} bytes, torn tail appended" -f $rowBytes, $observed)

# --- phase 3: reopen both stores, repair, 100% join integrity ---------------
$v1 = Invoke-Probe -Mode "verify" -OutName "hybrid-verify1"
Write-Host $v1.text.TrimEnd()
Check "verify #1 green: repair applied, 100% join integrity" ($v1.rc -eq 0 -and $v1.text.Contains("repaired=13"))
Check "verify #1: row store survived hard kill + torn tail" ($v1.text.Contains("all N rows recovered"))
Check "verify #1: join gate explicitly passed" ($v1.text.Contains("100% join integrity after repair") -and $v1.text.Contains("[PASS]"))

# --- phase 4: idempotent second verify (nothing left to repair) -------------
$v2 = Invoke-Probe -Mode "verify" -OutName "hybrid-verify2"
Check "verify #2 green: idempotent (repaired=0)" ($v2.rc -eq 0 -and $v2.text.Contains("repaired=0"))

Write-Host ("hybrid-crash: pass={0} fail={1}" -f $pass, $fail)
if ($fail -eq 0) { Write-Host "hybrid-crash: GREEN"; exit 0 }
Write-Host "hybrid-crash: RED"
exit 1
