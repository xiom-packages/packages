#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB runner -- compile+run one XIOM file under the tracked
# toolchain, with a hard watchdog and fail-closed exit-code handling.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\run.ps1 tests\suite\foundations.xi
#   .\scripts\run.ps1 tests\probes\probe_hello.xi -TimeoutSec 300
#
# Exit code: the program's reported exit code (or 1 on compile failure,
# 124 on watchdog timeout). Never treats a timeout or an empty run as green.
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$File,
    [int]$TimeoutSec = 120,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if (-not $env:XIOM_COMPILER -or -not (Test-Path -LiteralPath $env:XIOM_COMPILER)) {
    . (Join-Path $PSScriptRoot "dev-env.ps1")
    if (-not $env:XIOM_COMPILER) { throw "XIOM_COMPILER not resolved; check scripts\dev-env.ps1" }
}

$filePath = (Resolve-Path -LiteralPath $File).Path
$tmpRoot = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
$base = Join-Path $tmpRoot ("orbitdb-run-" + [guid]::NewGuid().ToString("N"))
$outFile = "$base.out"
$errFile = "$base.err"
# Unique output binary per invocation (S4 harness hardening): sharing a.exe in
# the repo root collides on DrvFs when a just-killed writer's image lingers
# ("Text file busy", os error 26) and cross-run overwrites race.
$binFile = "$base.exe"

Write-Host "run: $filePath"
Write-Host "  compiler:  $env:XIOM_COMPILER"
Write-Host "  watchdog:  ${TimeoutSec}s"

$proc = Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("--run", $filePath, "-o", $binFile) `
    -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile

$timedOut = $false
try {
    $proc | Wait-Process -Timeout $TimeoutSec -ErrorAction Stop
} catch {
    $timedOut = $true
}

if ($timedOut -and -not $proc.HasExited) {
    & taskkill /T /F /PID $proc.Id 2>$null | Out-Null
    Start-Sleep -Milliseconds 500
}

$stdout = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw } else { "" }
$stderr = if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Raw } else { "" }
Remove-Item -LiteralPath $outFile, $errFile, $binFile -ErrorAction SilentlyContinue
# No repo-root a.exe/a.out cleanup: with per-invocation -o binaries nothing is
# written there, and deleting another process's just-written binary on DrvFs
# is exactly the cross-run race this hardening removes.

$output = "$stdout$stderr"
if (-not $Quiet -and $output.Length -gt 0) { Write-Output $output.TrimEnd() }

if ($timedOut) {
    Write-Host "run: TIMEOUT after ${TimeoutSec}s -- process tree killed"
    exit 124
}

# `xiom --run` prints the program's exit code on its own "exit code:" line
# and can itself exit 0 even when the program crashed; trust the reported
# code (same rule as the PULSE lane's run.ps1).
$programExit = $null
$codeMatches = [regex]::Matches($output, "exit code:\s*(-?\d+)")
if ($codeMatches.Count -gt 0) {
    $programExit = [int64]$codeMatches[$codeMatches.Count - 1].Groups[1].Value
}
$effectiveExit = if ($null -ne $programExit) { $programExit } else { $proc.ExitCode }

Write-Host "run: program_exit=$effectiveExit compiler_exit=$($proc.ExitCode)"
exit $effectiveExit
