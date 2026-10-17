#!/usr/bin/env pwsh
# ============================================================================
# ORBITDB app build: compile one .xi source into an application binary and
# embed the ORBITDB Windows icon when the source tree provides it
# (compiler `--icon`, m214 -- compiles the .ico via llvm-rc).
#
# Usage: .\scripts\build.ps1 <source.xi> [-Out out\orbitdb-app.exe] [-TimeoutSec 300]
# Exit:  the compiler's exit code (0 = built).
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$File,
    [string]$Out = "",
    [int]$TimeoutSec = 300
)

# NOTE: the compiler prints warnings to stderr; do not set
# ErrorActionPreference=Stop (a native warning must not abort the build) --
# validity is decided by the compiler's exit code.

# Compiler resolution mirrors run.ps1: honor an existing XIOM_COMPILER, else
# dot-source the dev environment.
if (-not $env:XIOM_COMPILER) {
    . (Join-Path $PSScriptRoot "dev-env.ps1")
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$target = $File
if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path $repoRoot $target }
if (-not (Test-Path -LiteralPath $target)) {
    Write-Error "build: source not found: $target"
    exit 2
}

if (-not $Out) { $Out = Join-Path $repoRoot "out\orbitdb-app.exe" }
if (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path $repoRoot $Out }
New-Item -ItemType Directory -Path (Split-Path -Parent $Out) -Force | Out-Null

$toolArgs = @()
$icon = Join-Path $repoRoot "assets\orbitdb.ico"
if (Test-Path -LiteralPath $icon) {
    $toolArgs += @("--icon", $icon)
}
$toolArgs += @("--timeout", "$TimeoutSec", "-o", $Out, $target)

# dev-env.ps1 sets ErrorActionPreference=Stop; native stderr (progress and
# warnings) must not abort the build. The compiler's exit code is the truth.
$ErrorActionPreference = "Continue"
$buildOut = & $env:XIOM_COMPILER @toolArgs 2>&1
$buildCode = $LASTEXITCODE
foreach ($line in $buildOut) { Write-Host "$line" }
exit $buildCode
