#!/usr/bin/env pwsh
# xiom.android-sys A12 bridge -- on-device probe (evidence), 0.2.0 surface.
# Builds the driver + the five package bridges for x86_64-linux-android26,
# pushes them to the running emulator/device, runs the probe, then dumps
# logcat for the tag to prove the log writes landed in logd.
# Usage: powershell -File run-probe.ps1 [-Serial <adb serial>]
param([string]$Serial = "")

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# packages/xiom-android-sys/docs/repro/android-sys-probe -> repo root
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))))
$clang = "C:\Android\sdk\ndk\27.1.12297006\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
$adb = "C:\Android\sdk\platform-tools\adb.exe"
$srcDir = Join-Path $repo "packages\xiom-android-sys\src"
$out = Join-Path $env:TEMP "kilo\android-sys-probe"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$exe = Join-Path $out "android_sys_probe"

& $clang --target=x86_64-linux-android28 -fPIE -pie -O2 -o $exe (Join-Path $here "driver.c") `
    (Join-Path $srcDir "android_sys_bridge.c") `
    (Join-Path $srcDir "binder_bridge.c") `
    (Join-Path $srcDir "nnapi_bridge.c") `
    (Join-Path $srcDir "zlib_bridge.c") `
    (Join-Path $srcDir "icu_bridge.c") `
    -ldl
if ($LASTEXITCODE -ne 0) { throw "probe build failed" }

$serialArg = @()
if ($Serial -ne "") { $serialArg = @("-s", $Serial) }

& $adb @serialArg wait-for-device
& $adb @serialArg shell rm -f /data/local/tmp/xiom-spike/android_sys_probe | Out-Null
& $adb @serialArg push $exe /data/local/tmp/xiom-spike/android_sys_probe | Out-Null
& $adb @serialArg shell chmod +x /data/local/tmp/xiom-spike/android_sys_probe
& $adb @serialArg shell logcat -c
& $adb @serialArg shell /data/local/tmp/xiom-spike/android_sys_probe
$rc = $LASTEXITCODE
Write-Output "--- logcat proof (tag xiom-android-sys) ---"
& $adb @serialArg shell logcat -d -v brief -s xiom-android-sys
exit $rc
