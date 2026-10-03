# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Contract-coverage audit for the packages repo.
#
# Counts `requires:` / `ensures:` / `invariant:` clauses per package
# (src + root modules; tests/examples excluded), joins each package's
# stage (STATUS.json) and registry presence (packages/index.json), and
# prints coverage per segment so the stable-hardening queue (G4,
# docs/PROMOTION.md) can be sized at every wave.
#
# Read-only. Usage:
#   pwsh -File scripts/contract-coverage.ps1
#   pwsh -File scripts/contract-coverage.ps1 -Detailed

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$RegistryIndexPath,
    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'

# Resolve paths in the body: $PSScriptRoot is empty in param() defaults
# when the script is invoked with `powershell.exe -File`.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $scriptDir }

# Published = present in the LIVE registry index (packages/index.json is the
# repo-side index and includes unpublished/grandfathered entries).
$cache = Join-Path $env:TEMP 'kilo/registry-index.json'
if (-not $RegistryIndexPath) {
    try {
        $cacheDir = Split-Path -Parent $cache
        if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
        Invoke-WebRequest -Uri 'https://registry.xiom-lang.org/index.json' -OutFile $cache -UseBasicParsing -TimeoutSec 60
        $RegistryIndexPath = $cache
    } catch {
        if (Test-Path -LiteralPath $cache) {
            Write-Warning "registry fetch failed; using cached index at $cache"
            $RegistryIndexPath = $cache
        } else {
            Write-Warning "registry fetch failed and no cache; published flags will be false"
        }
    }
}

$published = @{}
if ($RegistryIndexPath -and (Test-Path -LiteralPath $RegistryIndexPath)) {
    $index = Get-Content -LiteralPath $RegistryIndexPath -Raw | ConvertFrom-Json
    foreach ($p in $index.packages.PSObject.Properties.Name) { $published[$p] = $true }
}

$rows = @()
Get-ChildItem (Join-Path $RepoRoot 'packages') -Directory | ForEach-Object {
    $manifest = Join-Path $_.FullName 'package.xi'
    if (-not (Test-Path -LiteralPath $manifest)) { return }

    $name = [regex]::Match((Get-Content -LiteralPath $manifest -Raw), 'name\s*:\s*"([^"]+)"').Groups[1].Value
    $req = 0; $ens = 0; $inv = 0

    Get-ChildItem $_.FullName -Recurse -Filter '*.xi' -File | ForEach-Object {
        if ($_.FullName -match '\\tests\\' -or $_.FullName -match '\\examples\\') { return }
        $text = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($_.FullName))
        $req += ([regex]::Matches($text, '(?m)^\s*requires\s*:')).Count
        $ens += ([regex]::Matches($text, '(?m)^\s*ensures\s*:')).Count
        $inv += ([regex]::Matches($text, '(?m)^\s*invariant\s*:')).Count
    }

    $stage = '?'
    $statusPath = Join-Path $_.FullName 'STATUS.json'
    if (Test-Path -LiteralPath $statusPath) {
        $stage = (Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json).stage
    }

    $rows += [pscustomobject]@{
        Name      = $name
        Stage     = $stage
        Published = [bool]$published[$name]
        Requires  = $req
        Ensures   = $ens
        Invariant = $inv
        Clauses   = $req + $ens + $inv
    }
}

Write-Host "contract-coverage: $($rows.Count) package(s); $((($rows | Measure-Object Clauses -Sum).Sum)) clause(s)"
Write-Host ""
Write-Host "segment                          packages  with-clauses  clauses"
foreach ($g in $rows | Group-Object { "$($_.Stage)/published=$($_.Published)" } | Sort-Object Name) {
    $with = @($g.Group | Where-Object { $_.Clauses -gt 0 }).Count
    Write-Host ("{0,-32} {1,8} {2,13} {3,8}" -f $g.Name, $g.Count, $with, (($g.Group | Measure-Object Clauses -Sum).Sum))
}

$stable = @($rows | Where-Object { $_.Stage -eq 'stable' -and $_.Published })
Write-Host ""
Write-Host "grandfathered stable: $($stable.Count) package(s); with clauses: $(@($stable | Where-Object { $_.Clauses -gt 0 }).Count); zero: $(@($stable | Where-Object { $_.Clauses -eq 0 }).Count)"

if ($Detailed) {
    Write-Host ""
    Write-Host "== published packages with clauses =="
    $rows | Where-Object { $_.Published -and $_.Clauses -gt 0 } | Sort-Object Clauses -Descending |
        ForEach-Object { Write-Host ("  {0,-24} stage={1,-11} req={2,-4} ens={3,-4} inv={4}" -f $_.Name, $_.Stage, $_.Requires, $_.Ensures, $_.Invariant) }
    Write-Host ""
    Write-Host "== zero-coverage stable names =="
    ($stable | Where-Object { $_.Clauses -eq 0 } | Sort-Object Name).Name -join ', '
}
