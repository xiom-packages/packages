#!/usr/bin/env pwsh
# xiom.android A1 bridge -- on-device probe (W2a evidence).
# Builds the driver + package bridge for x86_64-linux-android26, pushes
# both to the running emulator/device and runs it.
# Usage: powershell -File run-probe.ps1 [-Serial <adb serial>]
param([string]$Serial = "")

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# docs/repro/bindings-pilot/android-core-probe -> repo root
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
$clang = "C:\Android\sdk\ndk\27.1.12297006\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
$adb = "C:\Android\sdk\platform-tools\adb.exe"
$bridge = Join-Path $repo "packages\xiom-android\src\android_bridge.c"
$out = Join-Path $env:TEMP "kilo\android-core-probe"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$exe = Join-Path $out "android_core_probe"

& $clang --target=x86_64-linux-android26 -fPIE -pie -O2 -o $exe (Join-Path $here "driver.c") $bridge -ldl
if ($LASTEXITCODE -ne 0) { throw "probe build failed" }

$serialArg = @()
if ($Serial -ne "") { $serialArg = @("-s", $Serial) }

& $adb @serialArg push $exe /data/local/tmp/xiom-spike/android_core_probe | Out-Null
& $adb @serialArg shell chmod +x /data/local/tmp/xiom-spike/android_core_probe
& $adb @serialArg shell /data/local/tmp/xiom-spike/android_core_probe
exit $LASTEXITCODE
