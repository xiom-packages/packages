# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Fleet conformance sweep -- release-response detector (docs/MAINTENANCE.md).
#
# Runs `scripts/port.ps1 -TimeoutSec <n>` over every implemented package
# (stage stable/incubating/ported with a recorded green run) and writes one
# log per package plus a TSV summary under -LogDir. Resumable: re-running
# skips packages whose log already shows a PASS unless -Force is given.
#
# Read-only w.r.t. the repo (logs land in %TEMP%); recording runs is a
# separate, explicit status.ps1 step. Kill hygiene: port.ps1 kills its own
# process tree by PID; this script never kills on its own.
#
# Usage:
#   pwsh -File scripts/fleet-sweep.ps1                      # full sweep
#   pwsh -File scripts/fleet-sweep.ps1 -Only xiom.gbnf,xiom.ui
#   pwsh -File scripts/fleet-sweep.ps1 -Force               # ignore logs

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$LogDir,
    [int]$TimeoutSec = 60,
    [string[]]$Only = @(),
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

# Resolve paths in the body: $PSScriptRoot is empty in param() defaults
# when the script is invoked with `powershell.exe -File`.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $scriptDir }
if (-not $LogDir) { $LogDir = Join-Path $env:TEMP 'kilo/sweep' }
# `powershell.exe -File` passes `-Only a,b` as one string; split it.
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

$names = @()
Get-ChildItem (Join-Path $RepoRoot 'packages') -Directory | ForEach-Object {
    $manifest = Join-Path $_.FullName 'package.xi'
    $suite = Join-Path $_.FullName 'tests\test_conformance.xi'
    $status = Join-Path $_.FullName 'STATUS.json'
    if (-not ((Test-Path -LiteralPath $manifest) -and (Test-Path -LiteralPath $suite) -and (Test-Path -LiteralPath $status))) { return }
    $rec = Get-Content -LiteralPath $status -Raw | ConvertFrom-Json
    if ($rec.stage -notin @('stable', 'incubating', 'ported')) { return }
    if ($rec.tests.status -ne 'pass') { return }
    $name = [regex]::Match((Get-Content -LiteralPath $manifest -Raw), 'name\s*:\s*"([^"]+)"').Groups[1].Value
    if ($name) { $names += $name }
}
$names = @($names | Sort-Object -Unique)
if ($Only.Count -gt 0) { $names = @($names | Where-Object { $Only -contains $_ }) }

if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }

$tsv = Join-Path $LogDir 'summary.tsv'
$failed = Join-Path $LogDir 'failed.txt'
if ($Force) { Remove-Item -LiteralPath $tsv, $failed -ErrorAction SilentlyContinue }

$done = @{}
if ((Test-Path -LiteralPath $tsv) -and -not $Force) {
    Get-Content -LiteralPath $tsv | Select-Object -Skip 1 | ForEach-Object {
        $f = $_ -split "`t"
        if ($f.Count -ge 2 -and $f[1] -eq 'PASS') { $done[$f[0]] = $true }
    }
}
if (-not (Test-Path -LiteralPath $tsv)) {
    "name`tresult`tpassed`tfailed`texit`tseconds" | Set-Content -LiteralPath $tsv
}

$total = $names.Count
$i = 0
foreach ($name in $names) {
    $i++
    if ($done.ContainsKey($name)) {
        Write-Host "[$i/$total] $name SKIP (already PASS -- use -Force to re-run)"
        continue
    }
    $log = Join-Path $LogDir (($name -replace '[^A-Za-z0-9._-]', '_') + '.log')
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Invoke in a child process: port.ps1 uses Write-Host, which bypasses the
    # success stream in-process but IS captured at the process boundary.
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $portArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $scriptDir 'port.ps1'), '-Package', $name, '-TimeoutSec', "$TimeoutSec")
    $out = & $psExe @portArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    $sw.Stop()
    $text = ($out | Out-String)
    Set-Content -LiteralPath $log -Value $text
    $m = [regex]::Match($text, 'port: (?<res>PASS|FAIL) \(passed=(?<p>\d+) failed=(?<f>\d+)')
    $result = if ($m.Success) { $m.Groups['res'].Value } else { 'ERROR' }
    $passed = if ($m.Success) { $m.Groups['p'].Value } else { 0 }
    $failedN = if ($m.Success) { $m.Groups['f'].Value } else { 0 }
    "{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $name, $result, $passed, $failedN, $code, [math]::Round($sw.Elapsed.TotalSeconds, 1) | Add-Content -LiteralPath $tsv
    Write-Host ("[{0}/{1}] {2} {3} ({4}/{5}) {6}s" -f $i, $total, $name, $result, $passed, ([int]$passed + [int]$failedN), [math]::Round($sw.Elapsed.TotalSeconds, 1))
    if ($result -ne 'PASS') { Add-Content -LiteralPath $failed -Value $name }
}

$passN = @(Get-Content -LiteralPath $tsv | Select-Object -Skip 1 | Where-Object { ($_ -split "`t")[1] -eq 'PASS' }).Count
$failN = @(Get-Content -LiteralPath $tsv | Select-Object -Skip 1 | Where-Object { ($_ -split "`t")[1] -ne 'PASS' }).Count
Write-Host "fleet-sweep done: $passN PASS, $failN not-PASS; summary: $tsv"
