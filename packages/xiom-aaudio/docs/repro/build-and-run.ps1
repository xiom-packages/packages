#!/usr/bin/env pwsh
# xiom.aaudio A6 head -- on-device evidence driver (README.md).
# Builds the driver + the package bridge for x86_64-linux-android26,
# pushes both to the running emulator/device and runs it.
# Usage: powershell -File build-and-run.ps1 [-Serial <adb serial>]
param([string]$Serial = "")

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# packages/xiom-aaudio/docs/repro -> repo root
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
$clang = "C:\Android\sdk\ndk\27.1.12297006\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
$adb = "C:\Android\sdk\platform-tools\adb.exe"
$bridge = Join-Path $repo "packages\xiom-aaudio\src\aaudio_bridge.c"
$out = Join-Path $env:TEMP "kilo\aaudio-head-probe"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$exe = Join-Path $out "aaudio_head_probe"

& $clang --target=x86_64-linux-android26 -fPIE -pie -O2 -o $exe (Join-Path $here "aaudio_head_probe.c") $bridge -ldl
if ($LASTEXITCODE -ne 0) { throw "probe build failed" }

$serialArg = @()
if ($Serial -ne "") { $serialArg = @("-s", $Serial) }

& $adb @serialArg shell mkdir -p /data/local/tmp/xiom-spike | Out-Null
& $adb @serialArg push $exe /data/local/tmp/xiom-spike/aaudio_head_probe | Out-Null
& $adb @serialArg shell chmod +x /data/local/tmp/xiom-spike/aaudio_head_probe
& $adb @serialArg shell /data/local/tmp/xiom-spike/aaudio_head_probe
exit $LASTEXITCODE
