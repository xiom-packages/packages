#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB benchmark runner -- baseline numbers per compiler release.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Runs tests\probes\probe_bench.xi (btree insert/search/delete/range, tuple
# roundtrip, WAL append/replay) and tees the result to
# probe-logs\bench-<timestamp>.txt. Numbers are recorded in
# docs/PRODUCTION-READINESS.md (G1) -- regression baselines, not claims.
#
# Usage: .\scripts\bench.ps1 [-N 10000] [-Order 4]
# Exit:  0 = all cases ran.
# ============================================================================
[CmdletBinding()]
param(
    [int]$N = 10000,
    [int]$Order = 4
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

if (-not $env:XIOM_COMPILER -or -not (Test-Path -LiteralPath $env:XIOM_COMPILER)) {
    . (Join-Path $PSScriptRoot "dev-env.ps1")
    if (-not $env:XIOM_COMPILER) { throw "XIOM_COMPILER not resolved" }
}

$probe = Join-Path $repoRoot "tests\probes\probe_bench.xi"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $logDir "bench-$stamp.txt"

$env:ORBITDB_BENCH_N = "$N"
$env:ORBITDB_BENCH_ORDER = "$Order"
$env:ORBITDB_BENCH_CASE = "all"

Write-Host ("bench: n={0} order={1} -> {2}" -f $N, $Order, $out)
& (Join-Path $PSScriptRoot "run.ps1") $probe -TimeoutSec 900 | Tee-Object -FilePath $out
exit $LASTEXITCODE
