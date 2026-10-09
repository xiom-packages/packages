#!/usr/bin/env pwsh
# ============================================================================
# XIOM xiom.btree churn runner -- drives tests/probes/probe_btree_churn.xi.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Adapted from ORBITDB tests/probes/probe_btree_churn.xi env contract (commit
# c7d4901); pass-through only, no logic of its own beyond toolchain resolution
# and exit-code reporting.
#
# Toolchain: resolved by dot-sourcing the repo's scripts/xiom.ps1 (read-only).
# XIOM_COMPILER defaults to the brief's pin when unset.
#
# Usage:
#   powershell -NoProfile -File tests\churn.ps1 -Order 4 -Ops 20000 -N 4096
#   powershell -NoProfile -File tests\churn.ps1 -Order 4 -Ops 2000 -N 256 -Seed 12345 -Quiet
# Exit:  0 = probe green, nonzero = probe's exit code (124 = watchdog timeout).
# ============================================================================
[CmdletBinding()]
param(
    [int]$Order = 4,
    [int]$Ops = 2000,
    [int]$N = 256,
    [int]$Seed = 12345,
    [switch]$Quiet,
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = "Stop"

if (-not $env:XIOM_COMPILER -or -not (Test-Path -LiteralPath $env:XIOM_COMPILER)) {
    $env:XIOM_COMPILER = Join-Path $env:LOCALAPPDATA "xiom.new\bin\xiom.exe"
}
# Toolchain resolver: this checkout nests packages one level under the repo
# root, so try ..\..\..\scripts first and keep ..\..\scripts as fallback.
# Read-only in both cases.
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
$probe = Join-Path $PSScriptRoot "probes\probe_btree_churn.xi"
if (-not (Test-Path -LiteralPath $probe)) { throw "probe not found: $probe" }

$env:ORBITDB_CHURN_ORDER = "$Order"
$env:ORBITDB_CHURN_OPS = "$Ops"
$env:ORBITDB_CHURN_N = "$N"
$env:ORBITDB_CHURN_SEED = "$Seed"
if ($Quiet) { $env:ORBITDB_CHURN_QUIET = "1" } else { Remove-Item Env:ORBITDB_CHURN_QUIET -ErrorAction SilentlyContinue }

Write-Host ("churn: order={0} ops={1} n={2} seed={3} compiler={4} ({5})" -f $Order, $Ops, $N, $Seed, $tool.Version, $tool.Source)

$scratch = Join-Path $env:TEMP "kilo"
if (-not (Test-Path -LiteralPath $scratch)) { New-Item -ItemType Directory -Path $scratch | Out-Null }
$base = Join-Path $scratch ("churn-probe-" + [guid]::NewGuid().ToString("N"))
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
    if ($line.Trim()) { Write-Host $line.TrimEnd() }
}

$programExit = $null
$codeMatches = [regex]::Matches($output, "exit code:\s*(-?\d+)")
if ($codeMatches.Count -gt 0) {
    $programExit = [int64]$codeMatches[$codeMatches.Count - 1].Groups[1].Value
}
if ($timedOut) {
    Write-Host ("churn: RED (timeout after {0}s)" -f $TimeoutSec)
    exit 124
}
$code = if ($null -ne $programExit) { $programExit } else { $proc.ExitCode }
if ($code -eq 0) {
    Write-Host "churn: GREEN"
    exit 0
}
Write-Host ("churn: RED (exit={0})" -f $code)
exit $code
