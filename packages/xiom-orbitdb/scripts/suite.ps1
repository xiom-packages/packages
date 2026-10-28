#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB conformance-suite runner -- sums the split suite (R2).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   .\scripts\suite.ps1              # every tests\suite\*.xi, run twice
#   .\scripts\suite.ps1 -TimeoutSec 600
#
# Each suite file is a standalone program returning its failure count and
# printing `XIOM DB Conformance [<area>]: P/T passed`. This runner executes
# every file TWICE (the suite x2 rule), requires identical P/T in both rounds
# and zero failures, then sums the per-area counts. Exit 0 = green, 1 = red.
# ============================================================================
[CmdletBinding()]
param(
    [int]$TimeoutSec = 300
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$suiteDir = Join-Path $repoRoot "tests\suite"
$runner = Join-Path $PSScriptRoot "run.ps1"

if (-not (Test-Path -LiteralPath $suiteDir)) {
    Write-Host "suite: missing $suiteDir"
    exit 1
}

$files = @(Get-ChildItem -LiteralPath $suiteDir -Filter *.xi |
    Where-Object { $_.Name -ne "suite_common.xi" } |
    Sort-Object Name)
if ($files.Count -eq 0) {
    Write-Host "suite: no suite files found"
    exit 1
}

$sumPass = 0
$sumTotal = 0
$bad = 0

foreach ($f in $files) {
    $rounds = @()
    for ($round = 1; $round -le 2; $round++) {
        $out = & $runner $f.FullName -TimeoutSec $TimeoutSec 2>&1 | Out-String
        $rc = $LASTEXITCODE
        $m = [regex]::Match($out, "XIOM DB Conformance \[([a-z_]+)\]:\s*(\d+)/(\d+) passed")
        if (-not $m.Success) {
            Write-Host ("suite: {0} round {1}: NO SUMMARY (exit {2})" -f $f.Name, $round, $rc)
            if ($out -match "error\[") {
                $err = [regex]::Match($out, "(?m)^error.*$")
                if ($err.Success) { Write-Host ("  " + $err.Value) }
            }
            $bad++
            $rounds += $null
        } else {
            $p = [int]$m.Groups[2].Value
            $t = [int]$m.Groups[3].Value
            $rounds += [pscustomobject]@{ Pass = $p; Total = $t; Exit = $rc }
        }
    }

    if ($rounds[0] -eq $null -or $rounds[1] -eq $null) { continue }
    $r1 = $rounds[0]
    $r2 = $rounds[1]
    $consistent = ($r1.Pass -eq $r2.Pass) -and ($r1.Total -eq $r2.Total)
    $clean = ($r1.Exit -eq 0) -and ($r2.Exit -eq 0) -and ($r1.Pass -eq $r1.Total)
    if ($consistent -and $clean) {
        Write-Host ("suite: {0,-18} {1}/{2} x2" -f $f.BaseName, $r1.Pass, $r1.Total)
        $sumPass += $r1.Pass
        $sumTotal += $r1.Total
    } else {
        Write-Host ("suite: {0,-18} RED (r1 {1}/{2} exit {3}; r2 {4}/{5} exit {6})" -f `
            $f.BaseName, $r1.Pass, $r1.Total, $r1.Exit, $r2.Pass, $r2.Total, $r2.Exit)
        $bad++
    }
}

Write-Host ("suite: {0}/{1} passed x2 across {2} files" -f $sumPass, $sumTotal, $files.Count)
if ($bad -ne 0) {
    Write-Host "suite: RED"
    exit 1
}
Write-Host "suite: GREEN"
exit 0
