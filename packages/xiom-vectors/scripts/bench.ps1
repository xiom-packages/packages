#!/usr/bin/env pwsh
# ============================================================================
# XIOM XVECTOR benchmark runner (M-G2) -- build bench/bench_main.xi and run
# it under a watchdog. Mode via -Mode quick|medium|full (default medium).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\bench.ps1                 # medium
#   .\scripts\bench.ps1 -Mode quick     # CI smoke scale
#   .\scripts\bench.ps1 -Mode full      # large
# Exit code: 0 = green (report written); nonzero = failure.
# ============================================================================
[CmdletBinding()]
param(
    [ValidateSet("quick", "medium", "full")]
    [string]$Mode = "medium"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "lib.ps1")

$src = Join-Path $repoRoot "bench\bench_main.xi"
& (Join-Path $PSScriptRoot "build.ps1") $src -Name "bench_main"
if ($LASTEXITCODE -ne 0) { Write-Host "bench: build failed"; exit $LASTEXITCODE }

$env:XV_BENCH_MODE = $Mode
$exe = Join-Path $repoRoot "out\bench_main.exe"
$outFile = Join-Path $repoRoot "out\bench_main.out"
$errFile = Join-Path $repoRoot "out\bench_main.err"
$result = Invoke-XvectorProcess -FilePath $exe -WorkingDirectory $repoRoot `
    -StdOutFile $outFile -StdErrFile $errFile -TimeoutSec 900

if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile | ForEach-Object { Write-Host $_ } }
if ($result.TimedOut) { Write-Host "bench: TIMEOUT"; exit 124 }
if ($result.ExitCode -ne 0) {
    if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile | ForEach-Object { Write-Host "  $_" } }
    Write-Host "bench: FAILED (exit $($result.ExitCode))"
    exit $result.ExitCode
}
Write-Host "bench: GREEN ($Mode); report out\bench_report.json"
exit 0
