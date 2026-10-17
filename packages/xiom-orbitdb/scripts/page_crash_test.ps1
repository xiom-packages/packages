#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB page-file crash/reopen test -- durable page store primitive.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Drives tests\probes\probe_page_file.xi:
#   1. writer upserts N CRC32C-sealed pages, then hangs (crash simulation);
#   2. hard-kill the writer process tree once N pages are durable on disk;
#   3. append a torn tail (malformed, no newline) -- crash mid-write;
#   4. reopen: verify every page (count, checksum, byte pattern; torn skipped);
#   5. upsert one more page (rewrite heals the torn tail) and verify N+1.
#
# Usage: .\scripts\page_crash_test.ps1 [-Pages 20] [-TimeoutSec 90]
# Exit:  0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Pages = 20,
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

$probe = Join-Path $repoRoot "tests\probes\probe_page_file.xi"
$pageFile = Join-Path $logDir "crash-pages.seg"
if (Test-Path -LiteralPath $pageFile) { Remove-Item -LiteralPath $pageFile -Force }

$pass = 0; $fail = 0
function Check {
    param([string]$Name, [bool]$Ok)
    if ($Ok) { Write-Host "[PASS] $Name"; $script:pass++ }
    else { Write-Host "[FAIL] $Name"; $script:fail++ }
}

function Invoke-PageMode {
    param([string]$Mode, [int]$N, [string]$LastId = "")
    $env:ORBITDB_PAGE_FILE = $pageFile
    $env:ORBITDB_PAGE_MODE = $Mode
    $env:ORBITDB_PAGE_N = "$N"
    if ($LastId) { $env:ORBITDB_PAGE_LAST_ID = $LastId } else { Remove-Item Env:ORBITDB_PAGE_LAST_ID -ErrorAction SilentlyContinue }
    & (Join-Path $PSScriptRoot "run.ps1") $probe -TimeoutSec 180 -Quiet | Out-Null
    return $LASTEXITCODE
}

# --- phase 1: writer upserts Pages records, then hangs ----------------------
$env:ORBITDB_PAGE_FILE = $pageFile
$env:ORBITDB_PAGE_MODE = "write"
$env:ORBITDB_PAGE_N = "$Pages"
$writerOut = Join-Path $logDir "page-writer.out"
$writerErr = Join-Path $logDir "page-writer.err"
$writer = Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("--run", $probe, "-o", (Join-Path $logDir "page-writer-$PID.bin.exe")) `
    -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
    -RedirectStandardOutput $writerOut -RedirectStandardError $writerErr

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$observed = 0
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $pageFile) {
        $observed = @(Get-Content -LiteralPath $pageFile -ErrorAction SilentlyContinue).Count
        if ($observed -ge $Pages) { break }
    }
    if ($writer.HasExited) { break }
    Start-Sleep -Milliseconds 300
}
Check "writer wrote $Pages pages (observed=$observed)" ($observed -ge $Pages)

# --- phase 2: hard-kill + torn tail ----------------------------------------
if (-not $writer.HasExited) {
    try { & taskkill /T /F /PID $writer.Id | Out-Null } catch { }
    $writer.WaitForExit(10000) | Out-Null
}
Add-Content -LiteralPath $pageFile -Value "88|5|" -NoNewline
Write-Host ("crash: killed writer, page file={0} bytes, torn tail appended" -f (Get-Item -LiteralPath $pageFile).Length)

# --- phase 3: reopen, verify all pages despite the torn tail ---------------
$rc = Invoke-PageMode -Mode "verify" -N $Pages
Check "reopen verifies $Pages pages (checksums + pattern, torn skipped)" ($rc -eq 0)

# --- phase 4: upsert one more page (rewrite heals the torn tail) -----------
$rc = Invoke-PageMode -Mode "write1" -N $Pages
Check "upsert after torn tail heals (write1 exit 0)" ($rc -eq 0)

# --- phase 5: N+1 and last-page integrity -----------------------------------
$rc = Invoke-PageMode -Mode "verify" -N ($Pages + 1) -LastId "9999"
Check "reopen sees $($Pages + 1) pages incl. healed upsert" ($rc -eq 0)

Write-Host ("crash: pass={0} fail={1}" -f $pass, $fail)
if ($fail -eq 0) { Write-Host "page-crash: GREEN"; exit 0 }
Write-Host "page-crash: RED"
exit 1
