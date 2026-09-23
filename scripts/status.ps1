#!/usr/bin/env pwsh
# ============================================================================
# XIOM package readiness tracker -- validate/list/seed/update STATUS.json
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# STATUS.json lives inside each package folder (travels with the repo split).
# Schema (SESSION.md section 5):
#   package, stage, compiler, stdlib,
#   tests { suite, status, passed, failed, run_by, commit, checked },
#   publish, excluded_reason
#
# Rules enforced:
#   - stage in: incubating | ported | stable | deprecated
#   - publish: true requires stage stable
#   - stage stable requires a recorded green suite run (run_by + commit +
#     checked + status == pass)
#   - the subagent that works on a package records its own run; this script
#     never invents a run
#
# Usage:
#   .\scripts\status.ps1 -Action list
#   .\scripts\status.ps1 -Action validate
#   .\scripts\status.ps1 -Action seed
#   .\scripts\status.ps1 -Action update -Package xiom.lru -TestsStatus pass `
#       -Passed 12 -Failed 0 -RunBy "task:abc" -Commit 1234abc
# Exit code: 0 = ok, 1 = validation/update error.
# ============================================================================
[CmdletBinding()]
param(
    [ValidateSet("list", "validate", "seed", "update")]
    [string]$Action = "list",
    [string]$Package = "",
    [string]$Stage = "",
    [string]$TestsStatus = "",
    [int]$Passed = -1,
    [int]$Failed = -1,
    [string]$RunBy = "",
    [string]$Commit = "",
    [string]$Checked = "",
    [string]$ExcludedReason = "",
    [string]$Suite = "",
    [switch]$Publish,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$packagesDir = Join-Path $repoRoot "packages"
$allowlistFile = Join-Path $repoRoot ".github\publish-allowlist.txt"
$pinFile = Join-Path $repoRoot "COMPILER_VERSION"

$validStages = @("incubating", "ported", "stable", "deprecated")
$validTestStatus = @("unknown", "pass", "fail")

$pin = (Get-Content -LiteralPath $pinFile -Raw).Trim()
$defaultStdlibRange = ">=0.60.0 <1.0.0"

# Namespace audit 2026-09-23 (SESSION.md section 4): superseded by stdlib,
# pending owner confirmation. Seed as deprecated, never publish.
$deprecatedNames = @("xiom.math", "xiom.log", "xiom.net", "xiom.test")

# Implemented but deliberately not allowlisted; reasons mirror the allowlist
# comment block. These seed as incubating with publish=false + excluded_reason.
$reasonTable = @{
    "xiom.bullet"    = "not allowlisted: declaration-only (no function bodies)"
    "xiom.libsodium" = "not allowlisted: declaration-only (no function bodies)"
    "xiom.libuv"     = "not allowlisted: declaration-only (no function bodies)"
    "xiom.openal"    = "not allowlisted: declaration-only (no function bodies)"
    "xiom.ros2"      = "not allowlisted: declaration-only (no function bodies)"
    "xiom.stb"       = "not allowlisted: declaration-only (no function bodies)"
    "xiom.wasmtime"  = "not allowlisted: declaration-only (no function bodies)"
    "xiom.sql"       = "not allowlisted: stub body"
    "xiom.ffi"       = "not allowlisted: no source in this repo (stdlib owns the module)"
    "xiom.redis"     = "not allowlisted: FFI bridge not linked"
    "xiom.postgres"  = "not allowlisted: FFI bridge not linked"
    "xiom.libtorch"  = "not allowlisted: FFI bridge not linked"
    "xiom.numpy"     = "not allowlisted: FFI bridge not linked"
    "xiom.sqlite"    = "not allowlisted: FFI bridge not linked"
    "xiom.std"       = "platform package; published from the stdlib repository"
    "xiom.ecosystem" = "umbrella package; not a library artifact"
}

function Get-Allowlist {
    $names = Get-Content -LiteralPath $allowlistFile | Where-Object {
        $_.Trim() -ne "" -and -not $_.TrimStart().StartsWith("#")
    }
    return @($names | ForEach-Object { $_.Trim() })
}

function Get-ManifestName {
    param([string]$PackageDir)
    $manifest = Join-Path $PackageDir "package.xi"
    if (-not (Test-Path -LiteralPath $manifest)) { return "" }
    $content = Get-Content -LiteralPath $manifest -Raw
    if ($content -match 'name\s*:\s*"([^"]+)"') { return $Matches[1] }
    return ""
}

function Find-PackageDir {
    param([string]$Name)
    $direct = Join-Path $packagesDir $Name
    if (Test-Path -LiteralPath (Join-Path $direct "package.xi")) { return $direct }
    $hyphen = "xiom-" + ($Name -replace "^xiom\.", "")
    $byFolder = Join-Path $packagesDir $hyphen
    if (Test-Path -LiteralPath (Join-Path $byFolder "package.xi")) { return $byFolder }
    foreach ($d in (Get-ChildItem -LiteralPath $packagesDir -Directory)) {
        if ((Get-ManifestName $d.FullName) -eq $Name) { return $d.FullName }
    }
    return ""
}

function Find-TestSuite {
    param([string]$PackageDir)
    $testsDir = Join-Path $PackageDir "tests"
    if (-not (Test-Path -LiteralPath $testsDir)) { return "" }
    $conformance = Join-Path $testsDir "test_conformance.xi"
    if (Test-Path -LiteralPath $conformance) { return "tests/test_conformance.xi" }
    $short = (Split-Path -Leaf $PackageDir) -replace "^xiom-", ""
    $named = Join-Path $testsDir ("test_" + ($short -replace "-", "_") + ".xi")
    if (Test-Path -LiteralPath $named) { return ("tests/test_" + ($short -replace "-", "_") + ".xi") }
    $any = @(Get-ChildItem -LiteralPath $testsDir -Filter *.xi -File | Sort-Object Name)
    if ($any.Count -ge 1) { return ("tests/" + $any[0].Name) }
    return ""
}

function Write-StatusJson {
    param([string]$Path, [System.Collections.IDictionary]$Status)
    $json = $Status | ConvertTo-Json -Depth 6
    # PowerShell 5.1 escapes < > & as \uXXXX; keep the files readable.
    $json = $json -replace "\\u003c", "<" -replace "\\u003e", ">" -replace "\\u0026", "&"
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-StatusJson {
    param([string]$Path)
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Test-StatusObject {
    # Returns an array of problem strings for one STATUS.json ([] = clean).
    param([string]$PackageDir)
    $problems = @()
    $name = Split-Path -Leaf $PackageDir
    $statusPath = Join-Path $PackageDir "STATUS.json"
    if (-not (Test-Path -LiteralPath $statusPath)) {
        return @("missing STATUS.json")
    }
    try {
        $s = Get-StatusJson $statusPath
    } catch {
        return @("STATUS.json is not valid JSON: $($_.Exception.Message)")
    }

    foreach ($key in @("package", "stage", "compiler", "stdlib", "tests", "publish", "excluded_reason")) {
        if ($null -eq $s.PSObject.Properties[$key]) { $problems += "missing key '$key'" }
    }
    if ($problems.Count -gt 0) { return $problems }

    if ($s.stage -notin $validStages) { $problems += "invalid stage '$($s.stage)'" }
    if ($s.compiler -ne $pin) { $problems += "compiler '$($s.compiler)' != pin '$pin'" }

    $manifestName = Get-ManifestName $PackageDir
    if ($manifestName -and $s.package -ne $manifestName) {
        $problems += "package '$($s.package)' != manifest name '$manifestName'"
    }

    foreach ($key in @("suite", "status", "passed", "failed", "run_by", "commit", "checked")) {
        if ($null -eq $s.tests.PSObject.Properties[$key]) { $problems += "missing tests.$key" }
    }
    if ($s.tests.status -notin $validTestStatus) {
        $problems += "invalid tests.status '$($s.tests.status)'"
    } else {
        if ($s.tests.status -eq "unknown") {
            foreach ($key in @("passed", "failed", "run_by", "commit", "checked")) {
                if ($null -ne $s.tests.$key) { $problems += "tests.$key must be null when tests.status=unknown" }
            }
        } else {
            if ($null -eq $s.tests.passed -or $s.tests.failed -eq $null) {
                $problems += "tests.status=$($s.tests.status) requires passed/failed counts"
            }
            foreach ($key in @("run_by", "commit", "checked")) {
                if ([string]::IsNullOrWhiteSpace([string]$s.tests.$key)) {
                    $problems += "tests.status=$($s.tests.status) requires tests.$key"
                }
            }
        }
    }

    if ($s.publish -eq $true) {
        if ($s.stage -ne "stable") { $problems += "publish=true requires stage stable (is '$($s.stage)')" }
        if ($s.tests.status -ne "pass") { $problems += "publish=true requires tests.status=pass" }
    }
    if ($s.stage -eq "stable") {
        if ($s.tests.status -ne "pass") { $problems += "stage stable requires tests.status=pass" }
    }
    return $problems
}

function Get-ImplementedPackages {
    return @(Get-ChildItem -LiteralPath $packagesDir -Directory | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName "package.xi")
    } | Sort-Object Name)
}

# --- Actions ----------------------------------------------------------------

switch ($Action) {

    "seed" {
        $allowlist = Get-Allowlist
        $created = 0
        $skipped = 0
        foreach ($dir in (Get-ImplementedPackages)) {
            $name = Get-ManifestName $dir.FullName
            if (-not $name) { $name = $dir.Name }
            $statusPath = Join-Path $dir.FullName "STATUS.json"
            if ((Test-Path -LiteralPath $statusPath) -and -not $Force) {
                $skipped = $skipped + 1
                continue
            }

            $targetStage = "incubating"
            $reason = $null

            if ($name -in $deprecatedNames) {
                $targetStage = "deprecated"
                $reason = "superseded by stdlib (namespace audit 2026-09-23); pending owner confirmation"
            } elseif ($name -eq "xiom.core") {
                $reason = "blocked: pending rename to xiom.durable (owner confirmation; namespace audit 2026-09-23)"
            } elseif ($name -in $allowlist) {
                $reason = $null
            } elseif ($reasonTable.ContainsKey($name)) {
                $reason = $reasonTable[$name]
            } else {
                $reason = "not allowlisted: no readiness evidence recorded"
            }

            $status = [ordered]@{
                package         = $name
                stage           = $targetStage
                compiler        = $pin
                stdlib          = $defaultStdlibRange
                tests           = [ordered]@{
                    suite   = Find-TestSuite $dir.FullName
                    status  = "unknown"
                    passed  = $null
                    failed  = $null
                    run_by  = $null
                    commit  = $null
                    checked = $null
                }
                publish         = $false
                excluded_reason = $reason
            }
            Write-StatusJson -Path $statusPath -Status $status
            $created = $created + 1
        }
        Write-Host "status seed: created $created, skipped existing $skipped (use -Force to overwrite)"
        exit 0
    }

    "validate" {
        $errors = @()
        $pkgCount = 0
        foreach ($dir in (Get-ImplementedPackages)) {
            $pkgCount = $pkgCount + 1
            foreach ($p in (Test-StatusObject $dir.FullName)) {
                $errors += "$($dir.Name): $p"
            }
        }
        # Any STATUS.json outside an implemented package is a mistake.
        foreach ($f in (Get-ChildItem -LiteralPath $packagesDir -Recurse -Filter STATUS.json -File)) {
            $folder = Split-Path -Parent $f.FullName
            if (-not (Test-Path -LiteralPath (Join-Path $folder "package.xi"))) {
                $errors += "$(Split-Path -Leaf $folder): STATUS.json without package.xi (placeholders stay untouched)"
            }
        }
        if ($errors.Count -gt 0) {
            foreach ($e in $errors) { Write-Host "ERROR $e" }
            Write-Host "status validate: $pkgCount package(s), $($errors.Count) error(s)"
            exit 1
        }
        Write-Host "status validate: $pkgCount package(s), 0 errors"
        exit 0
    }

    "list" {
        $rows = @()
        foreach ($dir in (Get-ImplementedPackages)) {
            $statusPath = Join-Path $dir.FullName "STATUS.json"
            if (-not (Test-Path -LiteralPath $statusPath)) {
                $rows += [pscustomobject]@{
                    Package = (Get-ManifestName $dir.FullName)
                    Stage   = "<none>"
                    Tests   = "no STATUS.json"
                    Publish = $false
                    Checked = ""
                }
                continue
            }
            $s = Get-StatusJson $statusPath
            $tests = $s.tests.status
            if ($s.tests.status -eq "pass" -or $s.tests.status -eq "fail") {
                $tests = "$($s.tests.status) $($s.tests.passed)/$($s.tests.passed + $s.tests.failed)"
            }
            $rows += [pscustomobject]@{
                Package = $s.package
                Stage   = $s.stage
                Tests   = $tests
                Publish = [bool]$s.publish
                Checked = [string]$s.tests.checked
            }
        }
        $rows | Sort-Object Stage, Package | Format-Table -AutoSize
        exit 0
    }

    "update" {
        if (-not $Package) { throw "update requires -Package <name>" }
        $dir = Find-PackageDir $Package
        if (-not $dir) { throw "package not found: $Package" }
        $statusPath = Join-Path $dir "STATUS.json"
        if (-not (Test-Path -LiteralPath $statusPath)) {
            # Allow recording a run for a brand-new package whose STATUS.json
            # has not been seeded yet: build a minimal object first.
            $status = [ordered]@{
                package         = (Get-ManifestName $dir)
                stage           = "incubating"
                compiler        = $pin
                stdlib          = $defaultStdlibRange
                tests           = [ordered]@{ suite = (Find-TestSuite $dir); status = "unknown"; passed = $null; failed = $null; run_by = $null; commit = $null; checked = $null }
                publish         = $false
                excluded_reason = $null
            }
        } else {
            $s = Get-StatusJson $statusPath
            $status = [ordered]@{
                package         = $s.package
                stage           = $s.stage
                compiler        = $pin
                stdlib          = $s.stdlib
                tests           = [ordered]@{
                    suite   = $s.tests.suite
                    status  = $s.tests.status
                    passed  = $s.tests.passed
                    failed  = $s.tests.failed
                    run_by  = $s.tests.run_by
                    commit  = $s.tests.commit
                    checked = $s.tests.checked
                }
                publish         = [bool]$s.publish
                excluded_reason = $s.excluded_reason
            }
        }

        if ($Stage) {
            if ($Stage -notin $validStages) { throw "invalid stage: $Stage" }
            $status.stage = $Stage
        }
        if ($PSBoundParameters.ContainsKey("ExcludedReason")) { $status.excluded_reason = $ExcludedReason }
        if ($Suite) { $status.tests.suite = $Suite }
        if ($PSBoundParameters.ContainsKey("Publish")) { $status.publish = [bool]$Publish }

        if ($TestsStatus) {
            if ($TestsStatus -notin $validTestStatus) { throw "invalid TestsStatus: $TestsStatus" }
            if ($TestsStatus -eq "unknown") {
                $status.tests.status = "unknown"
                $status.tests.passed = $null
                $status.tests.failed = $null
                $status.tests.run_by = $null
                $status.tests.commit = $null
                $status.tests.checked = $null
            } else {
                if ($Passed -lt 0 -or $Failed -lt 0) { throw "recording a run requires -Passed <n> -Failed <n>" }
                if (-not $RunBy) { throw "recording a run requires -RunBy <agent id>" }
                if (-not $Commit) { throw "recording a run requires -Commit <sha of the tested tree>" }
                $status.tests.status = $TestsStatus
                $status.tests.passed = $Passed
                $status.tests.failed = $Failed
                $status.tests.run_by = $RunBy
                $status.tests.commit = $Commit
                if ($Checked) { $status.tests.checked = $Checked }
                else { $status.tests.checked = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
            }
        }

        # Enforce the readiness gates on the resulting object.
        if ($status.stage -eq "stable" -and $status.tests.status -ne "pass") {
            throw "refusing stage=stable without tests.status=pass (run the suite first)"
        }
        if ($status.publish -eq $true) {
            if ($status.stage -ne "stable") { throw "refusing publish=true without stage=stable" }
            if ($status.tests.status -ne "pass") { throw "refusing publish=true without a green recorded run" }
        }

        Write-StatusJson -Path $statusPath -Status $status
        Write-Host "status update: $($status.package) -> stage=$($status.stage) tests=$($status.tests.status) publish=$($status.publish)"
        exit 0
    }
}
