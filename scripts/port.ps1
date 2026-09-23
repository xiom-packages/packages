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
#      else compile each source module to a throwaway binary
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
    [switch]$NoRun
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

Push-Location $packageDir
try {
    if ($NoRun -or -not $suitePath -or -not (Test-Path -LiteralPath $suitePath)) {
        if ($suitePath -and -not (Test-Path -LiteralPath $suitePath)) {
            throw "suite not found: $suitePath"
        }
        Write-Host "  suite:    <none> -- compile-only check"
        $sources = @(Get-ChildItem -LiteralPath $packageDir -Recurse -Filter *.xi -File |
            Where-Object { $_.FullName -notmatch "\\(tests|\.git)\\" } |
            Sort-Object FullName)
        if ($sources.Count -eq 0) { throw "no source modules found in $packageDir" }
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "kilo\xiom-port"
        [void](New-Item -ItemType Directory -Force -Path $tmpDir)
        $i = 0
        foreach ($src in $sources) {
            $i = $i + 1
            $outExe = Join-Path $tmpDir ("check-" + $i + ".exe")
            Write-Host "  compile:  $($src.FullName.Substring($packageDir.Length + 1))"
            $result = Invoke-Compiler -Arguments @($src.FullName, "-o", $outExe)
            if ($result.ExitCode -ne 0) {
                Write-Host $result.Output
                $failed = $failed + 1
            }
        }
        if ($failed -eq 0) { $passed = $sources.Count }
        $exitCode = if ($failed -eq 0) { 0 } else { 1 }
    } else {
        Write-Host "  suite:    $suiteRel"
        $result = Invoke-Compiler -Arguments @("--run", $suitePath)
        $output = $result.Output
        $exitCode = $result.ExitCode
        Write-Host $output
        $passed = ([regex]::Matches($output, "\[PASS\]")).Count
        $failed = ([regex]::Matches($output, "\[FAIL\]")).Count
        if ($exitCode -ne 0) { $exitCode = 1 }
    }
} finally {
    Pop-Location
}

# 3. Summary.
$verdict = if ($exitCode -eq 0 -and $failed -eq 0) { "PASS" } else { "FAIL" }
Write-Host "port: $verdict (passed=$passed failed=$failed exit=$exitCode)"
if ($verdict -eq "PASS" -and -not $NoRun -and $suitePath) {
    Write-Host "record the run with:"
    Write-Host ("  .\scripts\status.ps1 -Action update -Package {0} -TestsStatus pass -Passed {1} -Failed {2} -RunBy <agent> -Commit <sha>" -f $name, $passed, $failed)
}
exit $exitCode
