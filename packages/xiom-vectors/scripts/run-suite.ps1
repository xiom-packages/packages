#!/usr/bin/env pwsh
# ============================================================================
# XIOM XVECTOR conformance runner -- build tests\test_conformance.xi and run
# it twice (x2 gate), each with a watchdog; gate on the process exit code.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: .\scripts\run-suite.ps1 [-Runs 2] [-TimeoutSec 60]
# Exit code: 0 = all runs green; nonzero = first failing run's exit code.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Runs = 2,
    [int]$TimeoutSec = 60,
    [switch]$Sequential
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repoRoot "tests\test_conformance.xi"
$exe = Join-Path $repoRoot "out\test_conformance.exe"
. (Join-Path $PSScriptRoot "lib.ps1")

& (Join-Path $PSScriptRoot "build.ps1") $src -Name "test_conformance" -Sequential:$Sequential
if ($LASTEXITCODE -ne 0) { Write-Host "run-suite: build failed"; exit $LASTEXITCODE }

$failedRun = 0
for ($i = 1; $i -le $Runs; $i++) {
    $outFile = Join-Path $repoRoot ("out\suite_run{0}.out" -f $i)
    $errFile = Join-Path $repoRoot ("out\suite_run{0}.err" -f $i)
    $result = Invoke-XvectorProcess -FilePath $exe -WorkingDirectory $repoRoot `
        -StdOutFile $outFile -StdErrFile $errFile -TimeoutSec $TimeoutSec

    $tail = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile | Select-Object -Last 2 } else { @() }
    $errCount = if (Test-Path -LiteralPath $errFile) { (Get-Content -LiteralPath $errFile).Count } else { 0 }

    if ($result.TimedOut) {
        Write-Host "run-suite: run ${i}: TIMEOUT after ${TimeoutSec}s"
        if ($failedRun -eq 0) { $failedRun = 124 }
    } elseif ($result.ExitCode -ne 0) {
        Write-Host "run-suite: run ${i}: FAILED (exit $($result.ExitCode))"
        $tail | ForEach-Object { Write-Host "  $_" }
        if ($failedRun -eq 0) { $failedRun = $result.ExitCode }
    } else {
        Write-Host "run-suite: run ${i}: GREEN (exit 0, stderr lines=$errCount)"
        $tail | ForEach-Object { Write-Host "  $_" }
    }
}

if ($failedRun -ne 0) { Write-Host "run-suite: FAILED"; exit $failedRun }
Write-Host "run-suite: ALL $Runs RUNS GREEN"
exit 0
