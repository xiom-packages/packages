#!/usr/bin/env pwsh
# ============================================================================
# XIOM toolchain resolver -- the supported way to invoke the compiler locally.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Resolution order (first usable candidate wins):
#   1. $env:XIOM_COMPILER     explicit override (always honored, even stale)
#   2. installed `xiom`       Get-Command xiom, used when version >= pin
#   3. repo release binaries  $env:XIOM_RELEASE_DIR or
#                             E:\xiom-lang\xiom\target\release (xiom.exe)
#
# The pin is COMPILER_VERSION at the repo root. A candidate older than the pin
# is only used when no newer candidate exists, and warns loudly. This mirrors
# SESSION.md section 7: agents use the pinned local compiler and never build
# the compiler from source unless the pin is unavailable.
#
# XIOM_STDLIB resolution: -Stdlib param > $env:XIOM_STDLIB > E:\xiom-lang\stdlib.
# The resolved path is exported as XIOM_STDLIB for every compiler invocation.
#
# Usage:
#   .\scripts\xiom.ps1 --version
#   .\scripts\xiom.ps1 --run tests\test_conformance.xi
#   .\scripts\xiom.ps1 -Info
#   . .\scripts\xiom.ps1          # dot-source: only defines the functions
# ============================================================================
[CmdletBinding()]
param(
    [string]$Stdlib = "",
    [switch]$Info,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CompilerArgs
)

$ErrorActionPreference = "Stop"

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:DefaultStdlib = "E:\xiom-lang\stdlib"
$script:DefaultReleaseDir = "E:\xiom-lang\xiom\target\release"

# --- Pinned version ---------------------------------------------------------

function Get-PinnedCompilerVersion {
    $pinFile = Join-Path $script:RepoRoot "COMPILER_VERSION"
    if (-not (Test-Path -LiteralPath $pinFile)) {
        throw "COMPILER_VERSION not found at $pinFile"
    }
    $pin = (Get-Content -LiteralPath $pinFile -Raw).Trim()
    if (-not $pin) { throw "COMPILER_VERSION is empty" }
    return $pin
}

# --- Version helpers --------------------------------------------------------

function Get-CompilerVersion {
    param([string]$ExePath)
    if (-not (Test-Path -LiteralPath $ExePath)) { return $null }
    try {
        $out = (& $ExePath --version 2>&1 | Out-String)
    } catch {
        return $null
    }
    if ($out -match "v?(\d+\.\d+\.\d+)") { return $Matches[1] }
    return $null
}

function Compare-VersionString {
    # Returns -1, 0, or 1. Falls back to string comparison on parse failure.
    param([string]$Left, [string]$Right)
    $l = $null; $r = $null
    try { $l = [version]($Left.TrimStart("v")) } catch { }
    try { $r = [version]($Right.TrimStart("v")) } catch { }
    if ($null -eq $l -or $null -eq $r) {
        return [string]::Compare($Left, $Right, [System.StringComparison]::Ordinal)
    }
    return $l.CompareTo($r)
}

# --- Resolution -------------------------------------------------------------

function Resolve-Compiler {
    $pin = Get-PinnedCompilerVersion
    $candidates = @()

    if ($env:XIOM_COMPILER) {
        if (Test-Path -LiteralPath $env:XIOM_COMPILER) {
            $candidates += @{ Path = (Resolve-Path -LiteralPath $env:XIOM_COMPILER).Path; Source = "XIOM_COMPILER" }
        } else {
            Write-Warning "XIOM_COMPILER is set but not found: $env:XIOM_COMPILER"
        }
    }

    $cmd = Get-Command xiom -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        $candidates += @{ Path = $cmd.Source; Source = "installed" }
    }

    $releaseDir = if ($env:XIOM_RELEASE_DIR) { $env:XIOM_RELEASE_DIR } else { $script:DefaultReleaseDir }
    $releaseExe = Join-Path $releaseDir "xiom.exe"
    if (Test-Path -LiteralPath $releaseExe) {
        $candidates += @{ Path = $releaseExe; Source = "repo-release" }
    }

    $resolved = @()
    foreach ($c in $candidates) {
        $version = Get-CompilerVersion -ExePath $c.Path
        $resolved += [pscustomobject]@{
            Path    = $c.Path
            Source  = $c.Source
            Version = $version
            Pin     = $pin
        }
    }

    if ($resolved.Count -eq 0) {
        throw "No XIOM compiler found. Set XIOM_COMPILER, install xiom, or provide $releaseExe."
    }

    foreach ($c in $resolved) {
        if ($c.Version -and (Compare-VersionString $c.Version $pin) -ge 0) {
            return $c
        }
    }

    $override = $resolved | Where-Object { $_.Source -eq "XIOM_COMPILER" } | Select-Object -First 1
    if ($override) {
        Write-Warning "XIOM_COMPILER ($($override.Version)) is older than the pin $pin; using it because it was set explicitly."
        return $override
    }

    $best = $resolved | Sort-Object { if ($_.Version) { $v = $null; try { $v = [version]$_.Version } catch { }; if ($v) { $v } else { [version]'0.0.0' } } } -Descending | Select-Object -First 1
    Write-Warning "No compiler >= pin $pin found; falling back to $($best.Source) $($best.Version). Upgrade before publishing."
    return $best
}

function Resolve-XiomToolchain {
    # Returns the resolved toolchain: Xiom (exe), Pkg (exe or $null),
    # Version, Source, Pin, Stdlib.
    param([string]$StdlibRoot = "")

    $compiler = Resolve-Compiler

    $stdlibPath = ""
    if ($StdlibRoot) { $stdlibPath = $StdlibRoot }
    elseif ($env:XIOM_STDLIB) { $stdlibPath = $env:XIOM_STDLIB }
    elseif (Test-Path -LiteralPath $script:DefaultStdlib) { $stdlibPath = $script:DefaultStdlib }

    if ($stdlibPath -and -not (Test-Path -LiteralPath $stdlibPath)) {
        throw "XIOM_STDLIB path not found: $stdlibPath"
    }
    if (-not $stdlibPath) {
        Write-Warning "No XIOM_STDLIB resolved (pass -Stdlib or set XIOM_STDLIB)."
    }

    $pkgExe = $null
    $pkgSibling = Join-Path (Split-Path -Parent $compiler.Path) "xiom-pkg.exe"
    if (Test-Path -LiteralPath $pkgSibling) { $pkgExe = $pkgSibling }

    return [pscustomobject]@{
        Xiom    = $compiler.Path
        Pkg     = $pkgExe
        Version = $compiler.Version
        Source  = $compiler.Source
        Pin     = $compiler.Pin
        Stdlib  = $stdlibPath
    }
}

# --- Runner -----------------------------------------------------------------

# Dot-sourced: define functions only, no side effects.
if ($MyInvocation.InvocationName -eq ".") { return }

$tool = Resolve-XiomToolchain -StdlibRoot $Stdlib
if ($tool.Stdlib) { $env:XIOM_STDLIB = $tool.Stdlib }

if ($Info -or $CompilerArgs.Count -eq 0) {
    Write-Host "xiom:        $($tool.Version) ($($tool.Source))"
    Write-Host "path:        $($tool.Xiom)"
    Write-Host "pin:         $($tool.Pin)"
    Write-Host "XIOM_STDLIB: $($tool.Stdlib)"
    if ($tool.Pkg) { Write-Host "xiom-pkg:    $($tool.Pkg)" }
}

if ($CompilerArgs.Count -gt 0) {
    & $tool.Xiom @CompilerArgs
    exit $LASTEXITCODE
}
exit 0
