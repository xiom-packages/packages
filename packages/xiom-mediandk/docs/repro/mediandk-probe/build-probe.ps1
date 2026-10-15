#!/usr/bin/env pwsh
# xiom.mediandk A7 bridge -- on-device probe builder/runner.
# 1. (optional) regenerates keys_expected.h from mediandk.xi via
#    gen-keys-expected.ps1 -- when present the driver runs the exhaustive
#    key-constant fidelity check instead of the dump mode.
# 2. builds the driver + package bridge for x86_64-linux-android26,
#    pushes both to the running emulator/device and runs it.
# Usage: pwsh build-probe.ps1 [-Serial <adb serial>] [-SkipExpected]
param([string]$Serial = "", [switch]$SkipExpected)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# packages/xiom-mediandk/docs/repro/mediandk-probe -> repo root
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))))
$clang = "C:\Android\sdk\ndk\27.1.12297006\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
$adb = "C:\Android\sdk\platform-tools\adb.exe"
$bridge = Join-Path $repo "packages\xiom-mediandk\src\mediandk_bridge.c"
$out = Join-Path $env:TEMP "kilo\mediandk-probe"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$exe = Join-Path $out "mediandk_probe"

if (-not $SkipExpected) {
    & (Join-Path $here "gen-keys-expected.ps1")
    if ($LASTEXITCODE -ne 0) { throw "keys_expected.h generation failed" }
}

& $clang --target=x86_64-linux-android26 -fPIE -pie -O2 -I $here -o $exe (Join-Path $here "mediandk_harness.c") $bridge -ldl
if ($LASTEXITCODE -ne 0) { throw "probe build failed" }

$serialArg = @()
if ($Serial -ne "") { $serialArg = @("-s", $Serial) }

& $adb @serialArg push $exe /data/local/tmp/xiom-spike/mediandk_probe | Out-Null
& $adb @serialArg shell chmod +x /data/local/tmp/xiom-spike/mediandk_probe
& $adb @serialArg shell /data/local/tmp/xiom-spike/mediandk_probe
exit $LASTEXITCODE
