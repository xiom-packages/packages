#!/usr/bin/env pwsh
# xiom.opensl A6 legacy-audio bridge -- on-device probe (W2d evidence).
# Builds the driver + package bridge for x86_64-linux-android26, pushes
# both to the running emulator/device and runs it.
# Usage: powershell -File run-probe.ps1 [-Serial <adb serial>]
param([string]$Serial = "")

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# packages/xiom-opensl/docs/repro/opensl-probe -> repo root
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here))))
$ndk = "C:\Android\sdk\ndk\27.1.12297006\toolchains\llvm\prebuilt\windows-x86_64"
$clang = "$ndk\bin\clang.exe"
$sysroot = "$ndk\sysroot\usr\include"
$adb = "C:\Android\sdk\platform-tools\adb.exe"
$bridge = Join-Path $repo "packages\xiom-opensl\src\opensl_bridge.c"
$out = Join-Path $env:TEMP "kilo\opensl-probe"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$exe = Join-Path $out "opensl_probe"

& $clang --target=x86_64-linux-android26 -fPIE -pie -O2 -isystem $sysroot -o $exe (Join-Path $here "driver.c") $bridge -ldl
if ($LASTEXITCODE -ne 0) { throw "probe build failed" }

$serialArg = @()
if ($Serial -ne "") { $serialArg = @("-s", $Serial) }

& $adb @serialArg push $exe /data/local/tmp/xiom-spike/opensl_probe | Out-Null
& $adb @serialArg shell chmod +x /data/local/tmp/xiom-spike/opensl_probe
& $adb @serialArg shell /data/local/tmp/xiom-spike/opensl_probe
exit $LASTEXITCODE
