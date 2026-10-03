# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Re-record green fleet-sweep runs into STATUS.json.
#
# Reads the TSV written by scripts/fleet-sweep.ps1 and calls
# `status.ps1 -Action update` for every PASS row, using the package's
# latest source commit as the record commit. Non-PASS rows are skipped
# (fix them first, then re-run fleet-sweep for those names).
#
# Usage:
#   pwsh -File scripts/record-sweep.ps1 -WhatIf
#   pwsh -File scripts/record-sweep.ps1 -RunBy "fleet-sweep:v0.62.3"

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$LogDir,
    [string]$RunBy = 'fleet-sweep:v0.62.3',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $scriptDir }
if (-not $LogDir) { $LogDir = Join-Path $env:TEMP 'kilo/sweep' }

$summary = Join-Path $LogDir 'summary.tsv'
if (-not (Test-Path -LiteralPath $summary)) { throw "summary not found: $summary" }

# name -> directory (dir names are not a mechanical transform: xiom.l10n.number
# lives in xiom-l10n-number), so map from the manifests.
$dirByName = @{}
Get-ChildItem (Join-Path $RepoRoot 'packages') -Directory | ForEach-Object {
    $manifest = Join-Path $_.FullName 'package.xi'
    if (-not (Test-Path -LiteralPath $manifest)) { return }
    $name = [regex]::Match((Get-Content -LiteralPath $manifest -Raw), 'name\s*:\s*"([^"]+)"').Groups[1].Value
    if ($name) { $dirByName[$name] = $_.Name }
}

$updated = 0
$skipped = 0
foreach ($line in (Get-Content -LiteralPath $summary | Select-Object -Skip 1)) {
    if (-not $line.Trim()) { continue }
    $f = $line -split "`t"
    $name = $f[0]; $result = $f[1]; $passed = $f[2]
    if ($result -ne 'PASS') { $skipped++; continue }
    $dir = $dirByName[$name]
    if (-not $dir) { Write-Warning "no directory for $name"; $skipped++; continue }
    # Source provenance: last commit touching the package's code/manifest,
    # not STATUS.json or README-only commits.
    $commit = (& git -C $RepoRoot log -1 --format=%h -- "packages/$dir/src" "packages/$dir/tests" "packages/$dir/*.xi").Trim()
    if (-not $commit) { Write-Warning "no source commit for $name"; $skipped++; continue }
    if ($WhatIf) {
        Write-Host "[whatif] $name -> pass $passed/0 run_by=$RunBy commit=$commit"
    } else {
        & (Join-Path $scriptDir 'status.ps1') -Action update -Package $name -TestsStatus pass -Passed ([int]$passed) -Failed 0 -RunBy $RunBy -Commit $commit | Out-Null
        Write-Host "recorded $name (pass $passed/0, $commit)"
    }
    $updated++
}

Write-Host "record-sweep: $updated record(s) $(if ($WhatIf) { 'planned' } else { 'written' }), $skipped non-PASS/skipped"
