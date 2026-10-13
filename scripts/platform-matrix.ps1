#!/usr/bin/env pwsh
# ============================================================================
# platform-matrix.ps1 -- docs/OFFLINE-INSTALL-DESIGN.md section 4 deliverable
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Per-package platform-support matrix generated from STATUS.json plus the
# shipped sources. Declared rows come from the optional STATUS fields
# `platforms` and `runtime_deps` (validated by scripts/status.ps1); rows
# without a declaration are derived and marked as such:
#   - compile            -> bundles C/C++ compiled at port time
#   - runtime-load       -> resolves an external library by soname at run time
#   - compile+runtime-load / pure
# Retrofit of declared rows happens at each package's next touch; new
# packages must land with one (same model as PROVENANCE.md). Report-only;
# exit 0 always.
#
# Usage:
#   .\scripts\platform-matrix.ps1                 # print summary only
#   .\scripts\platform-matrix.ps1 -WriteReport    # regenerate docs/PLATFORM-MATRIX.md
# ============================================================================

param(
    [switch]$WriteReport,
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptDir
$packagesRoot = Join-Path $root "packages"
$pin = (Get-Content -LiteralPath (Join-Path $root "COMPILER_VERSION") -Raw).Trim()

# Soname candidates in string literals, e.g. "SDL3.dll", "libvulkan.so.1".
$libRegex = [regex]'"([^"\r\n]+?\.(?:dll|dylib|so(?:\.[0-9]+)*))"'
# Test fixtures / build tooling / examples / docs are not shipped surface.
$sourceDirSkip = '\\tests\\|\\tools\\|\\examples\\|\\docs\\'
$sonameSkipPrefix = '^xiom-absent-'

function Get-ManifestField {
    param([string]$ManifestPath, [string]$Field)
    if (-not (Test-Path -LiteralPath $ManifestPath)) { return "" }
    $content = Get-Content -LiteralPath $ManifestPath -Raw
    if ($content -match ("(?m)" + [regex]::Escape($Field) + '\s*:\s*"([^"]*)"')) { return $Matches[1] }
    return ""
}

$rows = @()
foreach ($dir in (Get-ChildItem -LiteralPath $packagesRoot -Directory | Sort-Object Name)) {
    $manifest = Join-Path $dir.FullName "package.xi"
    if (-not (Test-Path -LiteralPath $manifest)) { continue }

    $name = Get-ManifestField $manifest "name"
    if (-not $name) { $name = $dir.Name }
    $version = Get-ManifestField $manifest "version"

    $statusPath = Join-Path $dir.FullName "STATUS.json"
    $stage = "(none)"
    $evidence = "-"
    $declaredPlatforms = @()
    $declaredDeps = @()
    if (Test-Path -LiteralPath $statusPath) {
        $s = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        $stage = [string]$s.stage
        if ($s.tests.status -eq "pass" -or $s.tests.status -eq "fail") {
            $evidence = "$($s.tests.status) $($s.tests.passed)/$($s.tests.passed + $s.tests.failed) @ $($s.tests.commit)"
        } else {
            $evidence = [string]$s.tests.status
        }
        $p = $s.PSObject.Properties["platforms"]
        if ($null -ne $p -and $null -ne $p.Value) { $declaredPlatforms = @($p.Value) }
        $d = $s.PSObject.Properties["runtime_deps"]
        if ($null -ne $d -and $null -ne $d.Value) { $declaredDeps = @($d.Value) }
    }

    # Derived native classification.
    $portArgsPath = Join-Path $dir.FullName "port.args.json"
    $portArgsC = 0
    $linkLibs = @()
    if (Test-Path -LiteralPath $portArgsPath) {
        $pa = @(Get-Content -LiteralPath $portArgsPath -Raw | ConvertFrom-Json)
        for ($i = 0; $i -lt $pa.Count; $i++) {
            if ($pa[$i] -in @("--c-source", "--cxx-source")) { $portArgsC++ }
            if ($pa[$i] -eq "--link" -and ($i + 1) -lt $pa.Count) { $linkLibs += [string]$pa[$i + 1] }
        }
    }
    $cFiles = @(Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in ".c", ".cpp", ".cc" -and
            $_.FullName -notmatch '\\tests\\' -and
            $_.FullName -notmatch '\\tools\\'
        })
    $compilesC = ($portArgsC -gt 0) -or ($cFiles.Count -gt 0)

    $sonames = @()
    foreach ($f in (Get-ChildItem -Path $dir.FullName -Recurse -File -Filter *.xi |
            Where-Object { $_.FullName -notmatch $sourceDirSkip })) {
        $text = Get-Content -LiteralPath $f.FullName -Raw
        foreach ($m in $libRegex.Matches($text)) {
            $cand = $m.Groups[1].Value
            if ($cand -notmatch $sonameSkipPrefix) { $sonames += $cand }
        }
    }
    $sonames = @($sonames | Sort-Object -Unique)
    $runtimeLoad = $sonames.Count -gt 0

    $class = "pure"
    if ($compilesC -and $runtimeLoad) { $class = "compile+runtime-load" }
    elseif ($compilesC) { $class = "compile" }
    elseif ($runtimeLoad) { $class = "runtime-load" }

    $isDeclared = ($declaredPlatforms.Count -gt 0)
    if ($isDeclared) { $platformsCell = ($declaredPlatforms -join ", ") }
    elseif ($class -eq "pure") { $platformsCell = "any (derived)" }
    else { $platformsCell = "undeclared" }

    $needsParts = @()
    if ($declaredDeps.Count -gt 0) {
        $needsParts += @($declaredDeps)
    } else {
        if ($runtimeLoad) {
            $shown = @($sonames | Select-Object -First 6)
            $extra = $sonames.Count - $shown.Count
            $cell = ($shown -join ", ")
            if ($extra -gt 0) { $cell += " (+$extra more; see SPEC)" }
            $needsParts += "$cell (runtime, derived)"
        }
        if ($linkLibs.Count -gt 0) { $needsParts += ("link: " + ($linkLibs -join ", ")) }
    }
    $needsCell = if ($needsParts.Count -gt 0) { $needsParts -join "; " } else { "-" }

    $rank = switch ($class) {
        "compile+runtime-load" { 1 }
        "compile" { 2 }
        "runtime-load" { 3 }
        "pure" { 4 }
    }

    $rows += [pscustomobject]@{
        Package   = $name
        Version   = $version
        Stage     = $stage
        Class     = $class
        Platforms = $platformsCell
        Needs     = $needsCell
        Evidence  = $evidence
        Declared  = $isDeclared
        Rank      = $rank
    }
}

$sorted = @($rows | Sort-Object @{ Expression = { if ($_.Declared) { 0 } else { 1 } } }, Rank, Package)
$declaredCount = @($rows | Where-Object { $_.Declared }).Count
$classCounts = @($rows | Group-Object Class | Sort-Object Name)
$nativeUndeclared = @($rows | Where-Object { -not $_.Declared -and $_.Class -ne "pure" })

$summary = "platform-matrix: $($rows.Count) package(s); declared=$declaredCount; " +
    (($classCounts | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join " ") +
    "; native pending declaration=$($nativeUndeclared.Count)"
Write-Host $summary

if ($WriteReport) {
    $out = if ($OutFile) { $OutFile } else { Join-Path $root "docs/PLATFORM-MATRIX.md" }
    $outDir = Split-Path -Parent $out
    if (-not (Test-Path -LiteralPath $outDir)) { [void](New-Item -ItemType Directory -Force -Path $outDir) }
    $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss'Z'")

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# XIOM Packages -- Platform Support Matrix")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("<!-- Generated by scripts/platform-matrix.ps1 -WriteReport. Do not edit by hand. -->")
    [void]$sb.AppendLine("<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->")
    [void]$sb.AppendLine("<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Toolchain pin: ``$pin`` -- generated $ts.")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## How to read this table")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- **Declared rows** are per-package statements recorded in ``STATUS.json``")
    [void]$sb.AppendLine("  (``platforms``, ``runtime_deps``). They are the certification; every package")
    [void]$sb.AppendLine("  declares one at its next touch and new packages must land with one.")
    [void]$sb.AppendLine("- **Derived rows** come from the shipped sources and are advisory:")
    [void]$sb.AppendLine("  - ``compile`` -- bundles C/C++ compiled at port time (``port.args.json``")
    [void]$sb.AppendLine("    ``--c-source``/``--cxx-source``, or shipped C sources such as a C bridge).")
    [void]$sb.AppendLine("  - ``runtime-load`` -- resolves an external library by soname at run time")
    [void]$sb.AppendLine("    (``xiom.ffi.dl``); at least one listed name must be present, and the")
    [void]$sb.AppendLine("    package reports a SKIP-style error when none is (see its SPEC).")
    [void]$sb.AppendLine("  - ``compile+runtime-load`` -- both of the above.")
    [void]$sb.AppendLine("  - ``pure`` -- no native boundary detected; runs wherever the pinned")
    [void]$sb.AppendLine("    toolchain runs (derived, not yet declared per package).")
    [void]$sb.AppendLine("- Platform tokens: ``windows-x64``, ``linux-x64``, ``macos-x64``,")
    [void]$sb.AppendLine("  ``macos-arm64``. ``any`` means no platform-specific boundary (pure XIOM).")
    [void]$sb.AppendLine("- Evidence is the recorded conformance run (status passed/total @ commit)")
    [void]$sb.AppendLine("  on the lane's Windows x64 box against the pinned compiler; it is not a")
    [void]$sb.AppendLine("  claim about other platforms.")
    [void]$sb.AppendLine("- ``undeclared`` native rows are the retrofit queue: declare ``platforms`` +")
    [void]$sb.AppendLine("  ``runtime_deps`` at the package's next touch.")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Declaring a row (STATUS.json schema)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Optional fields, validated by ``scripts/status.ps1 -Action validate`` and")
    [void]$sb.AppendLine("preserved by ``-Action repin``/``-Action update``:")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```json')
    [void]$sb.AppendLine('"platforms": ["windows-x64", "linux-x64"],')
    [void]$sb.AppendLine('"runtime_deps": ["vulkan-1.dll (loader; SKIP when absent)"]')
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- packages: $($rows.Count)")
    [void]$sb.AppendLine("- declared rows: $declaredCount")
    foreach ($g in $classCounts) {
        [void]$sb.AppendLine("- $($g.Name): $($g.Count)")
    }
    [void]$sb.AppendLine("- native packages pending declaration: $($nativeUndeclared.Count)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Declaration backlog (native)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine(($nativeUndeclared | ForEach-Object { $_.Package }) -join ", ")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Matrix")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Package | Version | Stage | Class | Platforms | Runtime needs | Evidence |")
    [void]$sb.AppendLine("|---|---|---|---|---|---|---|")
    foreach ($r in $sorted) {
        [void]$sb.AppendLine("| $($r.Package) | $($r.Version) | $($r.Stage) | $($r.Class) | $($r.Platforms) | $($r.Needs) | $($r.Evidence) |")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Related: ``docs/OFFLINE-INSTALL-DESIGN.md`` (flows A/B/C, blockers);")
    [void]$sb.AppendLine("``docs/PACKAGE_STATUS.md`` (stage + publish readiness).")
    [void]$sb.AppendLine("")

    [System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "report written: $out"
}
