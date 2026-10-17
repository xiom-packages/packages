#!/usr/bin/env pwsh
# ============================================================================
# xiom.numpy -- OPTIONAL real-leg acceleration probe runner.
# ============================================================================
# NOT the package conformance entry point. The offline gate stays
# `.\scripts\port.ps1 -Package xiom.numpy` (xiom.openblas stub leg,
# AccelLeg.SelfContained, no OpenBLAS required).
#
# This runner links tests/probe_numpy_real_leg.xi against a real OpenBLAS
# import library plus ../xiom-openblas/bridge/openblas_real_marker.c and
# asserts AccelLeg.OpenBlasReal with result equivalence to the offline
# goldens. `XIOM_NO_DEP_PORT_ARGS=1` is required: otherwise the path
# dependency's port.args.json auto-applies the stub bridge and lld reports a
# duplicate `xiom_openblas_backend` symbol.
#
# OpenBLAS discovery (first hit wins):
#   1. -OpenBlasRoot <dir>
#   2. $env:XIOM_OPENBLAS_ROOT
#   3. $env:XIOM_OPENBLAS_LIB (DLL path; root = its grandparent)
#   4. E:\repos\openblas\v0.3.34-x64 (pinned verification build)
#
# Missing library prints [SKIP] and exits 0. Use -Require to fail instead.
#
# Usage:
#   pwsh -File tests\run_real_leg.ps1
#   pwsh -File tests\run_real_leg.ps1 -Runs 2 -Require
# ============================================================================
[CmdletBinding()]
param(
    [string]$OpenBlasRoot = "",
    [int]$Runs = 2,
    [int]$TimeoutSec = 300,
    [switch]$Require
)

$ErrorActionPreference = "Stop"

$pkgDir = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $pkgDir)
. (Join-Path $repoRoot "scripts\xiom.ps1")
$tool = Resolve-XiomToolchain
if ($tool.Stdlib) { $env:XIOM_STDLIB = $tool.Stdlib }

function Get-CandidateRoots {
    $out = @()
    if ($OpenBlasRoot) { $out += $OpenBlasRoot }
    if ($env:XIOM_OPENBLAS_ROOT) { $out += $env:XIOM_OPENBLAS_ROOT }
    if ($env:XIOM_OPENBLAS_LIB) {
        $dllPath = $env:XIOM_OPENBLAS_LIB
        if (Test-Path -LiteralPath $dllPath) {
            $out += (Split-Path -Parent (Split-Path -Parent $dllPath))
        }
    }
    $out += "E:\repos\openblas\v0.3.34-x64"
    return $out
}

function Find-OpenBlasRoot {
    foreach ($candidate in (Get-CandidateRoots)) {
        if (-not $candidate) { continue }
        $dll = Join-Path $candidate "bin\libopenblas.dll"
        $libMsvc = Join-Path $candidate "lib\libopenblas.lib"
        $libMinGW = Join-Path $candidate "lib\libopenblas.dll.a"
        if ((Test-Path -LiteralPath $dll) -and ((Test-Path -LiteralPath $libMsvc) -or (Test-Path -LiteralPath $libMinGW))) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return ""
}

function Invoke-Probe {
    param([string[]]$Arguments, [int]$TimeoutSec)
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ("xiom-numpy-real-" + [guid]::NewGuid().ToString("N"))
    $outFile = "$base.out"
    $errFile = "$base.err"
    $proc = Start-Process -FilePath $tool.Xiom -ArgumentList $Arguments -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $timedOut = $false
    try {
        $proc | Wait-Process -Timeout $TimeoutSec -ErrorAction Stop
    } catch {
        $timedOut = $true
    }
    if ($timedOut -and -not $proc.HasExited) {
        & taskkill /T /F /PID $proc.Id 2>$null | Out-Null
        Start-Sleep -Milliseconds 500
    }
    $exitCode = if ($timedOut) { -1 } else { $proc.ExitCode }
    $stdout = if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile -Raw } else { "" }
    $stderr = if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Raw } else { "" }
    Remove-Item -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "a.exe", "a.exe.ll" -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        Output = ("$stdout$stderr")
        ExitCode = $exitCode
        TimedOut = $timedOut
        TimeoutSec = $TimeoutSec
    }
}

$root = Find-OpenBlasRoot
if (-not $root) {
    if ($Require) {
        Write-Host "[FAIL] no OpenBLAS build found (bin/libopenblas.dll + lib import library)"
        Write-Host "       tried: -OpenBlasRoot, XIOM_OPENBLAS_ROOT, XIOM_OPENBLAS_LIB, E:\repos\openblas\v0.3.34-x64"
        exit 2
    }
    Write-Host "[SKIP] no OpenBLAS build found -- offline suite: .\scripts\port.ps1 -Package xiom.numpy"
    exit 0
}

$configHeader = Join-Path $root "include\openblas_config.h"
if (Test-Path -LiteralPath $configHeader) {
    $ilp64 = Select-String -LiteralPath $configHeader -Pattern '^\s*#define\s+OPENBLAS_USE64BITINT' -Quiet
    if ($ilp64) {
        Write-Host "[FAIL] $root is an ILP64 build; xiom.openblas declares the int32 blasint ABI"
        exit 2
    }
}

$env:PATH = "$(Join-Path $root 'bin');$env:PATH"
# Suppress auto-applied dependency port.args: the stub bridge must not be
# linked together with the real marker (duplicate xiom_openblas_backend).
$env:XIOM_NO_DEP_PORT_ARGS = "1"

$probe = Join-Path $pkgDir "tests\probe_numpy_real_leg.xi"
$marker = Join-Path (Split-Path -Parent $pkgDir) "xiom-openblas\bridge\openblas_real_marker.c"
$arguments = @(
    "--run", "`"$probe`"",
    "--c-source", "`"$marker`"",
    "--link-path", "`"$(Join-Path $root 'lib')`"",
    "--link", "libopenblas",
    "--timeout", "$TimeoutSec"
)

Write-Host "real leg probe: xiom.numpy"
Write-Host "  openblas: $root"
Write-Host "  compiler: $($tool.Version) ($($tool.Source))"
Write-Host "  runs:     $Runs (timeout ${TimeoutSec}s each)"

$allGreen = $true
$runIndex = 1
while ($runIndex -le $Runs) {
    $result = Invoke-Probe -Arguments $arguments -TimeoutSec $TimeoutSec
    $passed = ([regex]::Matches($result.Output, "\[PASS\]")).Count
    $failed = ([regex]::Matches($result.Output, "\[FAIL\]")).Count
    $programExit = $null
    $matches = [regex]::Matches($result.Output, "exit code:\s*(-?\d+)")
    if ($matches.Count -gt 0) {
        $programExit = [int64]$matches[$matches.Count - 1].Groups[1].Value
    }
    $effectiveExit = if ($null -ne $programExit) { $programExit } else { $result.ExitCode }
    $green = (-not $result.TimedOut) -and $failed -eq 0 -and $passed -gt 0 -and $effectiveExit -eq 0
    if (-not $green) {
        $allGreen = $false
        Write-Host $result.Output
        Write-Host "run ${runIndex}: FAIL (passed=$passed failed=$failed program_exit=$effectiveExit timed_out=$($result.TimedOut))"
    } else {
        Write-Host "run ${runIndex}: PASS ($passed/$($passed + $failed) checks, program_exit=0)"
    }
    $runIndex = $runIndex + 1
}

if ($allGreen) {
    Write-Host "real leg probe: PASS ($Runs/$Runs runs green)"
    exit 0
}
Write-Host "real leg probe: FAIL"
exit 1
