#!/usr/bin/env pwsh
# ============================================================================
# XIOM XVECTOR probe runner -- build one probe and run it N times (default 2)
# with a watchdog; gate on exit code.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\run-probe.ps1 tests\probes\probe_hello.xi
#   .\scripts\run-probe.ps1 tests\probes\probe_vector_store.xi -Runs 2
# Exit code: 0 = all runs green; nonzero = first failing run's exit code.
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$File,
    [int]$Runs = 2,
    [int]$TimeoutSec = 60,
    [switch]$Sequential
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$filePath = (Resolve-Path -LiteralPath $File).Path
$name = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
$exe = Join-Path $repoRoot "out\$name.exe"
. (Join-Path $PSScriptRoot "lib.ps1")

& (Join-Path $PSScriptRoot "build.ps1") $filePath -Name $name -Sequential:$Sequential
if ($LASTEXITCODE -ne 0) { Write-Host "run-probe: build failed"; exit $LASTEXITCODE }

$failedRun = 0
for ($i = 1; $i -le $Runs; $i++) {
    $outFile = Join-Path $repoRoot ("out\{0}_run{1}.out" -f $name, $i)
    $errFile = Join-Path $repoRoot ("out\{0}_run{1}.err" -f $name, $i)
    $result = Invoke-XvectorProcess -FilePath $exe -WorkingDirectory $repoRoot `
        -StdOutFile $outFile -StdErrFile $errFile -TimeoutSec $TimeoutSec

    if ($result.TimedOut) {
        Write-Host "run-probe: run ${i}: TIMEOUT after ${TimeoutSec}s"
        if ($failedRun -eq 0) { $failedRun = 124 }
    } elseif ($result.ExitCode -ne 0) {
        Write-Host "run-probe: run ${i}: FAILED (exit $($result.ExitCode))"
        if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile | ForEach-Object { Write-Host "  $_" } }
        if ($failedRun -eq 0) { $failedRun = $result.ExitCode }
    } else {
        Write-Host "run-probe: run ${i}: GREEN (exit 0)"
        if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile | ForEach-Object { Write-Host "  $_" } }
    }
}

if ($failedRun -ne 0) { Write-Host "run-probe: FAILED"; exit $failedRun }
Write-Host "run-probe: ALL $Runs RUNS GREEN ($name)"
exit 0
