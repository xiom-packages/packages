#!/usr/bin/env pwsh
# xiom.jni A11 head -- on-device evidence driver (README.md).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# Licensed under the MIT or Apache-2.0 license, at your option.
#
# Two probes on the API-36 x86_64 emulator (ABI Medium_Phone_API_36.0):
#   1. shell probe (jni_head_probe.c + src/jni_bridge.c): the build-time
#      oracle gate (constants + all 56 table offsets vs the real r27b
#      headers), per-library dlopen + 9-export resolution, bridge loader,
#      on-device null-safety, and the honest no-VM answer of a plain
#      shell process.  Recorded to recorded-shell.txt.
#   2. app probe (jni_app_probe.c + Probe.java -> classes.dex via d8,
#      run through app_process): the LIVE JNIEnv seam -- JNI_OnLoad hands
#      the vm to the bridge; full call/string/array/exception/
#      RegisterNatives/thread-attach battery + the AndroidBitmap
#      roundtrip on a real Bitmap (write/read 0x11223344 + PNG compress).
#      Recorded to recorded-app.txt.
#
# The shell probe links at API 31 (libnativehelper.so is public since
# API 31; the emulator runs API 36).  The app .so links at API 26.
#
# Usage: powershell -File build-and-run.ps1 [-Serial <adb serial>]
#                                           [-SkipShell] [-SkipApp]
param(
  [string]$Serial = "",
  [switch]$SkipShell,
  [switch]$SkipApp
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# packages/xiom-jni/docs/repro -> repo root
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
$ndk = "C:\Android\sdk\ndk\27.1.12297006"
$clang = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
$adb = "C:\Android\sdk\platform-tools\adb.exe"
$bridge = Join-Path $repo "packages\xiom-jni\src\jni_bridge.c"
$out = Join-Path $env:TEMP "kilo\xj-probe"
New-Item -ItemType Directory -Path $out -Force | Out-Null

$serialArg = @()
if ($Serial -ne "") { $serialArg = @("-s", $Serial) }

$shellFail = 0
$appFail = 0

# -- 1. shell probe ----------------------------------------------------------
if (-not $SkipShell) {
  $exe = Join-Path $out "jni_head_probe"
  & $clang --target=x86_64-linux-android31 -fPIE -pie -O2 -Wall -I $here `
    -o $exe (Join-Path $here "jni_head_probe.c") $bridge -ljnigraphics -lnativehelper -ldl -lm
  if ($LASTEXITCODE -ne 0) { throw "shell probe build failed" }
  & $adb @serialArg shell mkdir -p /data/local/tmp/xiom-spike | Out-Null
  & $adb @serialArg push $exe /data/local/tmp/xiom-spike/jni_head_probe | Out-Null
  & $adb @serialArg shell chmod +x /data/local/tmp/xiom-spike/jni_head_probe
  $rec = Join-Path $here "recorded-shell.txt"
  $shellOut = & $adb @serialArg shell /data/local/tmp/xiom-spike/jni_head_probe
  $shellOut | Out-File -FilePath $rec -Encoding utf8
  $shellOut | ForEach-Object { $_ }
  if (-not ($shellOut | Select-String -SimpleMatch "XJ_PROBE RESULT: PASS" -Quiet)) { $shellFail = 1 }
  if ($shellFail -ne 0) { Write-Host "shell probe: FAIL (recorded to $rec)" } else { Write-Host "shell probe: PASS (recorded to $rec)" }
}

# -- 2. app probe (JNI_OnLoad seam via app_process) --------------------------
if (-not $SkipApp) {
  $soFile = Join-Path $out "libxjniprobe.so"
  & $clang --target=x86_64-linux-android26 -shared -fPIC -O2 -Wall `
    -o $soFile (Join-Path $here "jni_app_probe.c") $bridge -llog -lm
  if ($LASTEXITCODE -ne 0) { throw "app probe .so build failed" }

  # Java host -> classes.dex (javac + d8)
  $javaHome = "C:\Program Files\Eclipse Adoptium\jdk-17.0.16.8-hotspot"
  $javac = Join-Path $javaHome "bin\javac.exe"
  $d8 = "C:\Android\sdk\build-tools\36.0.0\d8.bat"
  $classesDir = Join-Path $out "classes"
  New-Item -ItemType Directory -Path $classesDir -Force | Out-Null
  & $javac -cp "C:\Android\sdk\platforms\android-36\android.jar" -d $classesDir (Join-Path $here "Probe.java")
  if ($LASTEXITCODE -ne 0) { throw "javac failed" }
  $dexDir = Join-Path $out "dex"
  New-Item -ItemType Directory -Path $dexDir -Force | Out-Null
  $env:JAVA_HOME = $javaHome
  & $d8 --lib "C:\Android\sdk\platforms\android-36\android.jar" --output $dexDir `
    (Join-Path $classesDir "com\xiom\jniprobe\Probe.class")
  if ($LASTEXITCODE -ne 0) { throw "d8 failed" }
  $dex = Join-Path $dexDir "classes.dex"
  if (-not (Test-Path -LiteralPath $dex)) { throw "d8 produced no classes.dex" }

  & $adb @serialArg push $soFile /data/local/tmp/xiom-spike/libxjniprobe.so | Out-Null
  & $adb @serialArg push $dex /data/local/tmp/xiom-spike/classes.dex | Out-Null
  & $adb @serialArg logcat -c
  $rec = Join-Path $here "recorded-app.txt"
  $runOut = & $adb @serialArg shell "CLASSPATH=/data/local/tmp/xiom-spike/classes.dex app_process /system/bin com.xiom.jniprobe.Probe"
  $runOut | Out-File -FilePath $rec -Encoding utf8
  $runOut | ForEach-Object { $_ }
  $log = & $adb @serialArg logcat -d -s "XIOM-A11:*"
  Add-Content -Path $rec -Value "`n== logcat (XIOM-A11) =="
  $log | ForEach-Object { Add-Content -Path $rec -Value $_; $_ }

  if ($runOut | Select-String -SimpleMatch "JNI_PROBE JAVA SIDE: PASS" -Quiet) { } else { $appFail = 1 }
  if ($log | Select-String -SimpleMatch "A11_SEAM fail=0" -Quiet) { } else { $appFail = 1 }
  if ($log | Select-String -SimpleMatch "A11_BITMAP fail=0" -Quiet) { } else { $appFail = 1 }
  if ($log | Select-String -SimpleMatch "  [FAIL]" -Quiet) { $appFail = 1 }
  if ($appFail -ne 0) { Write-Host "app probe: FAIL (recorded to $rec)" } else { Write-Host "app probe: PASS (recorded to $rec)" }
}

if ($shellFail -ne 0 -or $appFail -ne 0) { exit 1 }
exit 0
