#!/usr/bin/env pwsh
# ============================================================================
# XIOM namespace check -- enforces the SESSION.md section 4 rule.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Rule: a package may not declare modules equal to, or nested under, a stdlib
# module namespace. Concretely, a package module M collides with stdlib module
# S when M and S share the first two (or more) dotted segments -- i.e. they
# live in the same `xiom.<name>` namespace. Sharing only the root `xiom`
# segment is not a collision (every module does that).
#
# Examples flagged (the 2026-09-23 audit cases):
#   xiom.math.prelude  vs xiom.math.vectors
#   xiom.log.logger    vs xiom.log.color
#   xiom.net.dns       vs xiom.net.tcp
#   xiom.test          vs xiom.test.assert
#   xiom.core.pager    vs xiom.core.error
#
# Usage:
#   .\scripts\namespace-check.ps1                       # all implemented packages
#   .\scripts\namespace-check.ps1 -Package xiom-lru,xiom-ttl
#   .\scripts\namespace-check.ps1 -Stdlib E:\xiom-lang\stdlib
# Exit code: 0 = clean, 1 = collisions found.
# ============================================================================
[CmdletBinding()]
param(
    [string]$Stdlib = "",
    [string[]]$Package = @(),
    [string[]]$Module = @()
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$packagesDir = Join-Path $repoRoot "packages"

if (-not $Stdlib) {
    if ($env:XIOM_STDLIB) { $Stdlib = $env:XIOM_STDLIB }
    elseif (Test-Path -LiteralPath "E:\xiom-lang\stdlib") { $Stdlib = "E:\xiom-lang\stdlib" }
}
if (-not $Stdlib -or -not (Test-Path -LiteralPath $Stdlib)) {
    throw "stdlib root not found; pass -Stdlib or set XIOM_STDLIB"
}

# --- Collect stdlib module namespaces --------------------------------------

$stdlibFiles = @(Get-ChildItem -LiteralPath $Stdlib -Recurse -Filter *.xi -File -ErrorAction SilentlyContinue)
$moduleRegex = '^\s*module\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)'
$stdlibModules = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in ($stdlibFiles | Select-String -Pattern $moduleRegex)) {
    [void]$stdlibModules.Add($m.Matches[0].Groups[1].Value)
}
if ($stdlibModules.Count -eq 0) {
    throw "no module declarations found under $Stdlib"
}

function Get-CommonSegmentPrefixLength {
    # NOTE: variables are case-insensitive in PowerShell, so a typed param
    # `$A` reused as local `$a` coerces the array back to [string]. Use
    # distinct names.
    param([string]$Left, [string]$Right)
    $leftParts = $Left.Split('.')
    $rightParts = $Right.Split('.')
    $n = [Math]::Min($leftParts.Count, $rightParts.Count)
    $i = 0
    while ($i -lt $n -and $leftParts[$i] -eq $rightParts[$i]) { $i = $i + 1 }
    return $i
}

# --- Collect package modules ------------------------------------------------

function Get-PackageModules {
    param([string]$PackageDir)
    $modules = New-Object System.Collections.Generic.HashSet[string]

    $manifest = Join-Path $PackageDir "package.xi"
    if (Test-Path -LiteralPath $manifest) {
        $content = Get-Content -LiteralPath $manifest -Raw
        if ($content -match 'modules\s*:\s*\[([^\]]*)\]') {
            foreach ($q in ([regex]::Matches($Matches[1], '"([^"]+)"'))) {
                [void]$modules.Add($q.Groups[1].Value)
            }
        }
    }

    $files = @(Get-ChildItem -LiteralPath $PackageDir -Recurse -Filter *.xi -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch [regex]::Escape([IO.Path]::DirectorySeparatorChar + "tests" + [IO.Path]::DirectorySeparatorChar) })
    foreach ($m in ($files | Select-String -Pattern $moduleRegex)) {
        [void]$modules.Add($m.Matches[0].Groups[1].Value)
    }

    return @($modules)
}

function Get-PackageName {
    param([string]$PackageDir)
    $manifest = Join-Path $PackageDir "package.xi"
    if (Test-Path -LiteralPath $manifest) {
        $content = Get-Content -LiteralPath $manifest -Raw
        if ($content -match 'name\s*:\s*"([^"]+)"') { return $Matches[1] }
    }
    return (Split-Path -Leaf $PackageDir)
}

function Get-NamespaceHits {
    param([string]$Name)
    $hits = @()
    foreach ($s in $stdlibModules) {
        if ((Get-CommonSegmentPrefixLength -Left $Name -Right $s) -ge 2) { $hits += $s }
    }
    return @($hits | Sort-Object)
}

# --- Proposed module names (before a package folder/manifest exists) --------

if ($Module.Count -gt 0) {
    Write-Host "namespace-check: stdlib $Stdlib ($($stdlibModules.Count) module namespaces)"
    $violations = 0
    foreach ($m in $Module) {
        $hits = Get-NamespaceHits -Name $m
        if ($hits.Count -gt 0) {
            $violations = $violations + 1
            $sample = @($hits | Select-Object -First 3) -join ", "
            $more = if ($hits.Count -gt 3) { " (+$($hits.Count - 3) more)" } else { "" }
            Write-Host ("  {0,-24} CONFLICT -> stdlib: {1}{2}" -f $m, $sample, $more)
        } else {
            Write-Host ("  {0,-24} OK" -f $m)
        }
    }
    Write-Host ("namespace-check: {0} proposed module(s), {1} conflict(s)" -f $Module.Count, $violations)
    if ($violations -gt 0) { exit 1 }
    exit 0
}

# --- Select packages --------------------------------------------------------

$dirs = @(Get-ChildItem -LiteralPath $packagesDir -Directory | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName "package.xi")
} | Sort-Object Name)

if ($Package.Count -gt 0) {
    $wanted = @{}
    foreach ($p in $Package) { $wanted[$p] = $true }
    $dirs = @($dirs | Where-Object {
        $name = Get-PackageName $_.FullName
        $wanted.ContainsKey($name) -or $wanted.ContainsKey($_.Name)
    })
    if ($dirs.Count -eq 0) { throw "no implemented package matched: $($Package -join ', ')" }
}

# --- Check ------------------------------------------------------------------

Write-Host "namespace-check: stdlib $Stdlib ($($stdlibModules.Count) module namespaces)"
$violations = 0
$checkedModules = 0

foreach ($dir in $dirs) {
    $name = Get-PackageName $dir.FullName
    $modules = Get-PackageModules $dir.FullName
    $conflicts = @()

    foreach ($m in $modules) {
        $checkedModules = $checkedModules + 1
        $hits = Get-NamespaceHits -Name $m
        if ($hits.Count -gt 0) {
            $sample = @($hits | Select-Object -First 3) -join ", "
            $conflicts += [pscustomobject]@{ Module = $m; Stdlib = $sample; Count = $hits.Count }
        }
    }

    if ($conflicts.Count -gt 0) {
        $violations = $violations + $conflicts.Count
        Write-Host ("  {0,-24} CONFLICT ({1} module(s))" -f $name, $conflicts.Count)
        foreach ($c in $conflicts) {
            Write-Host ("      {0}  ->  stdlib: {1}{2}" -f $c.Module, $c.Stdlib, $(if ($c.Count -gt 3) { " (+$($c.Count - 3) more)" } else { "" }))
        }
    } else {
        Write-Host ("  {0,-24} OK ({1} module(s))" -f $name, $modules.Count)
    }
}

Write-Host ("namespace-check: {0} package(s), {1} module(s), {2} conflict(s)" -f $dirs.Count, $checkedModules, $violations)
if ($violations -gt 0) { exit 1 }
exit 0
