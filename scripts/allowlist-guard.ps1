#!/usr/bin/env pwsh
# ============================================================================
# Readiness guard -- the publish allowlist may never drift ahead of readiness.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# For every name in .github/publish-allowlist.txt:
#   - the package must be `stage: stable` with `tests.status: pass` in its
#     STATUS.json (the same record that produces docs/PACKAGE_STATUS.md),
#   - EXCEPT names listed in .github/allowlist-baseline.txt: those predate the
#     readiness model (the 2026-09-21/23 gate pass), are reported loudly every
#     run, and do not fail the build until they are ported.
#
# Adding a name to the allowlist is the publish approval step; this guard is
# what makes that approval auditable. Never add a name to the baseline -- that
# would bypass the guard. Emptying the baseline enforces full strictness.
#
# Usage (local and CI):
#   pwsh -NoProfile -File scripts/allowlist-guard.ps1
# Exit code: 0 = no allowlist entry is ahead of readiness, 1 = at least one is.
# ============================================================================
[CmdletBinding()]
param(
    [string]$AllowlistPath = "",
    [string]$BaselinePath = "",
    [string]$PackagesPath = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $AllowlistPath) { $AllowlistPath = Join-Path $repoRoot ".github/publish-allowlist.txt" }
if (-not $BaselinePath) { $BaselinePath = Join-Path $repoRoot ".github/allowlist-baseline.txt" }
if (-not $PackagesPath) { $PackagesPath = Join-Path $repoRoot "packages" }

function Read-Names {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(Get-Content -LiteralPath $Path |
        Where-Object { $_.Trim() -ne "" -and -not $_.TrimStart().StartsWith("#") } |
        ForEach-Object { $_.Trim() })
}

$allowlist = Read-Names -Path $AllowlistPath
$baseline = Read-Names -Path $BaselinePath
if ($allowlist.Count -eq 0) {
    Write-Host "allowlist-guard: allowlist is empty ($AllowlistPath)"
    exit 0
}

$statuses = @{}
foreach ($f in (Get-ChildItem -LiteralPath $PackagesPath -Recurse -Filter STATUS.json -File)) {
    try {
        $s = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        $statuses[[string]$s.package] = $s
    } catch {
        Write-Host "allowlist-guard: WARN unreadable STATUS.json: $($f.FullName)"
    }
}

$baselineSet = @{}
foreach ($b in $baseline) { $baselineSet[$b] = $true }

$ready = @()
$grandfathered = @()
$failures = @()

foreach ($name in $allowlist) {
    $s = $statuses[$name]
    $isReady = ($null -ne $s -and $s.stage -eq "stable" -and $s.tests.status -eq "pass")
    if ($isReady) { $ready += $name; continue }
    $detail = if ($null -eq $s) { "no STATUS.json" } else { "stage=$($s.stage) tests=$($s.tests.status)" }
    if ($baselineSet.ContainsKey($name)) { $grandfathered += "$name ($detail)"; continue }
    $failures += "$name ($detail)"
}

foreach ($name in $baseline) {
    if ($allowlist -notcontains $name) {
        Write-Host "allowlist-guard: WARN baseline name is no longer allowlisted: $name"
    }
}

foreach ($g in ($grandfathered | Sort-Object)) {
    Write-Host "allowlist-guard: GRANDFATHERED (not ready, pre-baseline entry): $g"
}
foreach ($f in ($failures | Sort-Object)) {
    Write-Host "allowlist-guard: FAIL: $f"
}

$summary = "allowlist-guard: $($allowlist.Count) allowlisted, $($ready.Count) ready, " +
    "$($grandfathered.Count) grandfathered (not ready), $($failures.Count) failure(s)"
Write-Host $summary

if ($env:GITHUB_STEP_SUMMARY) {
    $lines = @(
        "## Readiness guard",
        "",
        $summary,
        "",
        "| Check | Count |",
        "|---|---|",
        "| allowlisted | $($allowlist.Count) |",
        "| stable + green | $($ready.Count) |",
        "| grandfathered (not ready) | $($grandfathered.Count) |",
        "| **failures** | **$($failures.Count)** |"
    )
    if ($failures.Count -gt 0) {
        $lines += @("", "Failures:", "")
        foreach ($f in ($failures | Sort-Object)) { $lines += "- $f" }
    }
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $lines
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
