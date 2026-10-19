#!/usr/bin/env pwsh
# ============================================================================
# arm64 emulation harness -- run a package suite (or a .xi file) under
# Docker Desktop's linux/arm64 emulation (qemu-backed).
# ============================================================================
# Proven 2026-10-19: official xiom-0.64.7/0.64.8 linux-arm64 build + clang-19
# (trixie image) + qemu -> xiom.mqtt suite green. Use --timeout 0 inside the
# container: the emulated clang link exceeds the 300s default compile cap.
#
# Prerequisites:
#   - Docker Desktop running with arm64 emulation (docker run --platform)
#   - the linux-arm64 compiler tarball extracted at -CompilerRoot
#     (e.g. E:\repos\xiom-arm64 with bin/xiom)
#   - a toolchain image with clang: docker build --platform linux/arm64
#     -t xiom-arm64-emu:trixie <this-> Dockerfile (debian:trixie-slim + clang)
#
# Usage:
#   .\scripts\emulate-arm64.ps1 -Package mqtt
#   .\scripts\emulate-arm64.ps1 -Package xiom.gpio
#   .\scripts\emulate-arm64.ps1 -File docs\repro\bindings-pilot\ptr-arith\probe.xi
# ============================================================================
param(
    [string]$Package = "",
    [string]$File = "",
    [string]$CompilerRoot = "E:\repos\xiom-arm64",
    [string]$Stdlib = "E:\xiom-lang\stdlib",
    [string]$Image = "xiom-arm64-emu:trixie",
    [int]$CompileTimeoutSec = 0,
    [int]$HardTimeoutSec = 1200
)

$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot

if (-not $Package -and -not $File) {
    throw "Pass -Package <name> (e.g. mqtt or xiom.mqtt) or -File <repo-relative .xi path>"
}

if ($Package) {
    $name = $Package -replace '^xiom\.', ''
    $rel = "packages/xiom-$name/tests/test_conformance.xi"
} else {
    $rel = ($File -replace '\\', '/') -replace '^\./', ''
    if (-not (Test-Path -LiteralPath (Join-Path $repo $rel))) {
        throw "File not found under the repo: $rel"
    }
}

$target = "/repo/$rel"
$cmd = "timeout $HardTimeoutSec env XIOM_STDLIB=/stdlib /xiom/bin/xiom --timeout $CompileTimeoutSec --run '$target'"

Write-Host "arm64 emulation: $rel"
Write-Host "  image:  $Image"
Write-Host "  xiom:   $CompilerRoot/bin/xiom (arm64)"
Write-Host "  stdlib: $Stdlib"
Write-Host ""

docker run --rm --platform linux/arm64 `
    -v "${CompilerRoot}:/xiom" `
    -v "${repo}:/repo" `
    -v "${Stdlib}:/stdlib" `
    -w /tmp $Image sh -c $cmd
exit $LASTEXITCODE
