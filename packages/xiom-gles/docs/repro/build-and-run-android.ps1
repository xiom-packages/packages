#!/usr/bin/env pwsh
# xiom.gles A9 android leg -- on-device evidence driver (README.md).
#
# Cross-builds the runtime bridge (src/gles_probe.c) + this package's probe
# (docs/repro/gles_android_probe.c) with the NDK r27b clang for BOTH
# aarch64-linux-android26 (C-bundle check: ELF machine + readelf) and
# x86_64-linux-android26 (the emulator ABI), pushes the x86_64 probe to
# /data/local/tmp/xiom-spike, runs it, and records the transcript to
# recorded-gles-android.txt next to this script.
#
# The probe drives the SAME bridge the XIOM module loads: candidate sonames
# (libEGL.so + libGLESv2.so/v3/v1_CM) -> display -> GL strings ->
# eglQueryString(EGL_EXTENSIONS) -> one real GLES2 context -> glClear.
#
# Usage: powershell -File build-and-run-android.ps1 [-Serial <adb serial>]
#                                                    [-SkipRun]
param(
  [string]$Serial = "",
  [switch]$SkipRun
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# docs/repro -> package root
$pkg = Split-Path -Parent (Split-Path -Parent $here)
$ndk = "C:\Android\sdk\ndk\27.1.12297006"
$bin = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin"
$clang = Join-Path $bin "clang.exe"
$readelf = Join-Path $bin "llvm-readelf.exe"
$adb = "C:\Android\sdk\platform-tools\adb.exe"
$bridge = Join-Path $pkg "src\gles_probe.c"
$probe = Join-Path $here "gles_android_probe.c"
$out = Join-Path $env:TEMP "kilo\gles-android-probe"
New-Item -ItemType Directory -Path $out -Force | Out-Null
$rec = Join-Path $here "recorded-gles-android.txt"

if (-not (Test-Path $clang)) { throw "NDK clang not found: $clang" }

$serialArg = @()
if ($Serial -ne "") { $serialArg = @("-s", $Serial) }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("xiom.gles A9 android leg -- recorded on-device run (build-and-run-android.ps1)")
$lines.Add("NDK: r27b 27.1.12297006; clang: $((& $clang --version | Select-Object -First 1))")
$lines.Add("")

# -- 1. aarch64-linux-android26: cross-build only (C-bundle check) ----------
$arm = Join-Path $out "gles_android_probe_arm64"
$armLog = & $clang --target=aarch64-linux-android26 -fPIE -pie -O2 -Wall `
  -o $arm $probe $bridge -ldl -lm 2>&1
if ($LASTEXITCODE -ne 0) { throw "aarch64 cross-build failed: $armLog" }
$armElf = & $readelf -h $arm | Select-String "Machine|Class|Type" | ForEach-Object { $_.Line.Trim() }
$lines.Add("--- aarch64-linux-android26 cross-build (build-only; no arm64 device) ---")
$lines.Add("artifact: $arm ($((Get-Item $arm).Length) bytes)")
$lines.Add(($armElf -join " | "))
$lines.Add("")
Write-Host "aarch64 cross-build: OK"

# -- 2. x86_64-linux-android26: cross-build + emulator run ------------------
$exe = Join-Path $out "gles_android_probe"
$xLog = & $clang --target=x86_64-linux-android26 -fPIE -pie -O2 -Wall `
  -o $exe $probe $bridge -ldl -lm 2>&1
if ($LASTEXITCODE -ne 0) { throw "x86_64 cross-build failed: $xLog" }
$lines.Add("--- x86_64-linux-android26 cross-build ---")
$lines.Add("artifact: $exe ($((Get-Item $exe).Length) bytes)")
$lines.Add("")
Write-Host "x86_64 cross-build: OK"

if (-not $SkipRun) {
  $devices = & $adb devices | Select-String "device$"
  if (-not $devices) { throw "no adb device/emulator attached (start Medium_Phone_API_36.0 first)" }
  & $adb @serialArg shell mkdir -p /data/local/tmp/xiom-spike | Out-Null
  & $adb @serialArg push $exe /data/local/tmp/xiom-spike/gles_android_probe | Out-Null
  & $adb @serialArg shell chmod +x /data/local/tmp/xiom-spike/gles_android_probe

  $lines.Add("--- on-device run (adb shell) ---")
  $runOut = & $adb @serialArg shell /data/local/tmp/xiom-spike/gles_android_probe
  $runCode = $LASTEXITCODE
  $runOut | ForEach-Object { $lines.Add($_) }
  $lines.Add("probe exit code: $runCode")
  $lines.Add("")

  $pass = ($runOut | Select-String -SimpleMatch "RESULT: PASS" -Quiet)
  $lines.Add("verdict: " + $(if ($pass -and $runCode -eq 0) { "PASS" } else { "FAIL" }))
} else {
  $lines.Add("--- on-device run skipped (-SkipRun) ---")
}

$lines | Out-File -FilePath $rec -Encoding utf8
Write-Host "recorded: $rec"
if (-not $SkipRun) {
  Get-Content $rec | Select-Object -Last 40
} 
