#!/usr/bin/env pwsh
# ============================================================================
# XIOM package porter -- compile a package and run its conformance suite.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# What it does, in order:
#   1. resolve the toolchain via scripts/xiom.ps1 (pin-aware, sets XIOM_STDLIB)
#   2. enforce the section-4 namespace rule via scripts/namespace-check.ps1
#   3. compile the package: `xiom --run tests/<suite>` when a suite exists,
#      else type-check/lower each source module with `xiom --emit-ir`
#      (no linking, so library modules without fn main are valid)
#   4. print the suite summary and the exact `status.ps1 -Action update`
#      command to record the run
#
# It NEVER changes stage or publish, and never writes STATUS.json itself.
#
# Usage:
#   .\scripts\port.ps1 -Package xiom.lru
#   .\scripts\port.ps1 -Package xiom-hello -Suite tests\test_hello.xi
#   .\scripts\port.ps1 -Package xiom.hello -NoRun
# Exit code: 0 = green, 1 = compile/test failure, 3 = namespace conflict.
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Package,
    [string]$Suite = "",
    [switch]$NoRun,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot "xiom.ps1")
$tool = Resolve-XiomToolchain
if ($tool.Stdlib) { $env:XIOM_STDLIB = $tool.Stdlib }

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
    $packagesDir = Join-Path $repoRoot "packages"
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
    $any = @(Get-ChildItem -LiteralPath $testsDir -Filter *.xi -File | Sort-Object Name)
    if ($any.Count -ge 1) { return ("tests/" + $any[0].Name) }
    return ""
}

function Invoke-Compiler {
    # Runs the compiler with stdout/stderr captured to files. PowerShell 5.1
    # turns native stderr into ErrorRecords, which aborts under
    # ErrorActionPreference=Stop, so file redirection is the reliable capture.
    param([string[]]$Arguments)
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ("xiom-run-" + [guid]::NewGuid().ToString("N"))
    $outFile = "$base.out"
    $errFile = "$base.err"
    $proc = Start-Process -FilePath $tool.Xiom -ArgumentList $Arguments -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $stdout = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw } else { "" }
    $stderr = if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Raw } else { "" }
    Remove-Item -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Output = ("$stdout$stderr"); ExitCode = $proc.ExitCode }
}

$packageDir = Find-PackageDir $Package
if (-not $packageDir) { throw "package not found (no package.xi): $Package" }
$name = Get-ManifestName $packageDir
if (-not $name) { throw "package.xi has no name field: $packageDir" }

Write-Host "port: $name"
Write-Host "  dir:      $packageDir"
Write-Host "  compiler: $($tool.Version) ($($tool.Source))"
Write-Host "  stdlib:   $($tool.Stdlib)"

# 1. Namespace rule (section 4).
$nsScript = Join-Path $PSScriptRoot "namespace-check.ps1"
& $nsScript -Package $name -Stdlib $tool.Stdlib
if ($LASTEXITCODE -ne 0) {
    Write-Host "port: ABORT -- namespace conflict; fix modules before compiling"
    exit 3
}

# 2. Compile + run.
$suiteRel = $Suite
if (-not $suiteRel) { $suiteRel = Find-TestSuite $packageDir }
$suitePath = ""
if ($suiteRel) { $suitePath = Join-Path $packageDir $suiteRel }

$passed = 0
$failed = 0
$exitCode = 0
$effectiveExit = 0

Push-Location $packageDir
try {
    if ($NoRun -or -not $suitePath -or -not (Test-Path -LiteralPath $suitePath)) {
        if ($suitePath -and -not (Test-Path -LiteralPath $suitePath)) {
            throw "suite not found: $suitePath"
        }
        Write-Host "  suite:    <none> -- compile-only check"
        $sources = @(Get-ChildItem -LiteralPath $packageDir -Recurse -Filter *.xi -File |
            Where-Object { $_.Name -ne "package.xi" -and $_.FullName -notmatch "\\(tests|\.git)\\" } |
            Sort-Object FullName)
        if ($sources.Count -eq 0) { throw "no source modules found in $packageDir" }
        foreach ($src in $sources) {
            Write-Host "  compile:  $($src.FullName.Substring($packageDir.Length + 1))"
            # --emit-ir type-checks and lowers without linking, so library
            # modules (no fn main) can be checked too (the old -o path failed
            # with "undefined symbol: main" for every library package).
            $result = Invoke-Compiler -Arguments @("--emit-ir", $src.FullName)
            if ($result.ExitCode -ne 0) {
                Write-Host $result.Output
                $failed = $failed + 1
            }
        }
        if ($failed -eq 0) { $passed = $sources.Count }
        $effectiveExit = if ($failed -eq 0) { 0 } else { 1 }
        $exitCode = $effectiveExit
    } else {
        Write-Host "  suite:    $suiteRel"
        $result = Invoke-Compiler -Arguments @("--run", $suitePath)
        $output = $result.Output
        if (-not $Quiet) { Write-Host $output }
        $passed = ([regex]::Matches($output, "\[PASS\]")).Count
        $failed = ([regex]::Matches($output, "\[FAIL\]")).Count
        # `xiom --run` prints the program's exit code on its own "exit code:"
        # line and can itself exit 0 even when the program crashed (observed
        # with an access violation, -1073741819). Trust the reported code.
        $programExit = $null
        $codeMatches = [regex]::Matches($output, "exit code:\s*(-?\d+)")
        if ($codeMatches.Count -gt 0) {
            $programExit = [int64]$codeMatches[$codeMatches.Count - 1].Groups[1].Value
        }
        $effectiveExit = if ($null -ne $programExit) { $programExit } else { $result.ExitCode }
        # Fail-closed: a suite run that produced no [PASS] markers at all
        # (empty output, interrupted run, or a program that never executed
        # its checks) must not be accepted as green.
        $exitCode = if ($effectiveExit -eq 0 -and $failed -eq 0 -and $passed -gt 0) { 0 } else { 1 }
    }
} finally {
    Pop-Location
}

# 3. Summary.
$verdict = if ($exitCode -eq 0 -and $failed -eq 0) { "PASS" } else { "FAIL" }
Write-Host "port: $verdict (passed=$passed failed=$failed program_exit=$effectiveExit exit=$exitCode)"
if ($verdict -eq "PASS" -and -not $NoRun -and $suitePath) {
    Write-Host "record the run with:"
    Write-Host ("  .\scripts\status.ps1 -Action update -Package {0} -TestsStatus pass -Passed {1} -Failed {2} -RunBy <agent> -Commit <sha>" -f $name, $passed, $failed)
}
exit $exitCode
