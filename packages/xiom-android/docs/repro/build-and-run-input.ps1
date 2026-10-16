#!/usr/bin/env pwsh
# xiom.android A3 input + A4 sensors heads -- on-device evidence driver
# (README.md).  Two binaries:
#   1. shell probe (input_head_probe.c + src/android_bridge.c): cross-built
#      for x86_64-linux-android26, pushed to /data/local/tmp/xiom-spike,
#      run; the full A4 path + the A3 explicit-error contract + the
#      build-time constant gate (gen/a3a4_const_asserts.h).  Output is
#      recorded to recorded-input-shell.txt.
#   2. app probe (input_app_probe.c + native_app_glue + the same bridge):
#      a C-only NativeActivity APK (hasCode=false) with the framework-
#      delivered AInputQueue -- the live attach/detach + key/motion
#      event-read proof.  Installed, launched, fed with
#      `input keyevent 29` / `input tap 540 1200` / `input keyevent 30`;
#      the XIOM-A3 logcat is recorded to recorded-input-app.txt.
# Usage: powershell -File build-and-run-input.ps1 [-Serial <adb serial>]
#                                                 [-SkipShell] [-SkipApp]
param(
  [string]$Serial = "",
  [switch]$SkipShell,
  [switch]$SkipApp
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# packages/xiom-android/docs/repro -> repo root
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
$ndk = "C:\Android\sdk\ndk\27.1.12297006"
$clang = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
$glueDir = Join-Path $ndk "sources\android\native_app_glue"
$adb = "C:\Android\sdk\platform-tools\adb.exe"
$bridge = Join-Path $repo "packages\xiom-android\src\android_bridge.c"
$out = Join-Path $env:TEMP "kilo\android-input-probe"
New-Item -ItemType Directory -Path $out -Force | Out-Null

$serialArg = @()
if ($Serial -ne "") { $serialArg = @("-s", $Serial) }

$shellFail = 0
$appFail = 0

# -- 1. shell probe ----------------------------------------------------------
if (-not $SkipShell) {
  $exe = Join-Path $out "input_head_probe"
  & $clang --target=x86_64-linux-android26 -fPIE -pie -O2 -Wall -I $here `
    -o $exe (Join-Path $here "input_head_probe.c") $bridge -ldl -lm
  if ($LASTEXITCODE -ne 0) { throw "shell probe build failed" }
  & $adb @serialArg shell mkdir -p /data/local/tmp/xiom-spike | Out-Null
  & $adb @serialArg push $exe /data/local/tmp/xiom-spike/input_head_probe | Out-Null
  & $adb @serialArg shell chmod +x /data/local/tmp/xiom-spike/input_head_probe
  $rec = Join-Path $here "recorded-input-shell.txt"
  $shellOut = & $adb @serialArg shell /data/local/tmp/xiom-spike/input_head_probe
  $shellOut | Out-File -FilePath $rec -Encoding utf8
  $shellOut | ForEach-Object { $_ }
  if ($LASTEXITCODE -ne 0) { $shellFail = 1 }
  if (-not ($shellOut | Select-String -SimpleMatch "RESULT: PASS" -Quiet)) { $shellFail = 1 }
  if ($shellFail -ne 0) { Write-Host "shell probe: FAIL (recorded to $rec)" } else { Write-Host "shell probe: PASS (recorded to $rec)" }
}

# -- 2. app probe (C-only NativeActivity APK) --------------------------------
if (-not $SkipApp) {
  $bt = "C:\Android\sdk\build-tools\36.0.0"
  $aapt2 = Join-Path $bt "aapt2.exe"
  $zipalign = Join-Path $bt "zipalign.exe"
  $apksigner = Join-Path $bt "apksigner.bat"
  $androidJar = "C:\Android\sdk\platforms\android-36\android.jar"
  $keystore = Join-Path $env:USERPROFILE ".android\debug.keystore"

  $apkDir = Join-Path $out "apk"
  $libDir = Join-Path $apkDir "lib\x86_64"
  New-Item -ItemType Directory -Path $libDir -Force | Out-Null
  $so = Join-Path $libDir "libxiom_input_probe.so"
  & $clang --target=x86_64-linux-android26 -shared -fPIC -O2 -Wall -I $glueDir -I $here `
    -o $so (Join-Path $here "input_app_probe.c") `
    (Join-Path $glueDir "android_native_app_glue.c") $bridge -landroid -llog -lm -ldl
  if ($LASTEXITCODE -ne 0) { throw "app probe .so build failed" }

  $manifest = Join-Path $apkDir "AndroidManifest.xml"
  @"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.xiom.inputprobe">
  <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="36"/>
  <application android:label="XIOM A3 probe" android:hasCode="false"
               android:extractNativeLibs="true">
    <activity android:name="android.app.NativeActivity" android:exported="true">
      <meta-data android:name="android.app.lib_name" android:value="xiom_input_probe"/>
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
"@ | Out-File -FilePath $manifest -Encoding utf8

  $baseApk = Join-Path $apkDir "base.apk"
  & $aapt2 link -o $baseApk --manifest $manifest -I $androidJar `
    --min-sdk-version 26 --target-sdk-version 36
  if ($LASTEXITCODE -ne 0) { throw "aapt2 link failed" }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::Open($baseApk, 'Update')
  try {
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
      $zip, $so, "lib/x86_64/libxiom_input_probe.so",
      [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  } finally { $zip.Dispose() }

  $aligned = Join-Path $apkDir "base-aligned.apk"
  & $zipalign -f 4 $baseApk $aligned
  if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }

  $env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.16.8-hotspot"
  $env:Path = "$env:JAVA_HOME\bin;$env:Path"
  $signed = Join-Path $apkDir "input-probe-signed.apk"
  & $apksigner sign --ks $keystore --ks-pass pass:android --key-pass pass:android `
    --ks-key-alias androiddebugkey --out $signed $aligned
  if ($LASTEXITCODE -ne 0) { throw "apksigner failed" }

  & $adb @serialArg install -r $signed
  if ($LASTEXITCODE -ne 0) { throw "adb install failed" }

  & $adb @serialArg logcat -c
  & $adb @serialArg shell am start -n com.xiom.inputprobe/android.app.NativeActivity
  Start-Sleep -Seconds 5

  # documented block (captured while the app is live): touch injection is
  # refused for this window -- the dispatcher lists its InputWindowInfo
  # with frame=[0,0][0,0] / touchableRegion=<empty>; appended verbatim so
  # the limitation is recorded, never papered over.
  $deadline = (Get-Date).AddSeconds(20)
  do {
    $focus = & $adb @serialArg shell dumpsys window | Select-String -Pattern 'mCurrentFocus=.*inputprobe'
  } while (-not $focus -and (Get-Date) -lt $deadline)
  $di = & $adb @serialArg shell dumpsys input
  # the LIVE entry: the previous instance's dying window lingers in the
  # list briefly, so match the focused (inputConfig=0x0) entry only.
  $block = @($di | Select-String -Pattern 'com\.xiom\.inputprobe/android\.app\.NativeActivity,.*inputConfig=0x0' -Context 0,2 |
             Select-Object -First 1 | ForEach-Object { $_.Line.Trim(); $_.Context.PostContext | ForEach-Object { $_.Trim() } })

  & $adb @serialArg shell input keyevent 29   # AKEYCODE_A (down + up)
  Start-Sleep -Seconds 3
  & $adb @serialArg shell input keyevent 30   # AKEYCODE_B (down + up)
  Start-Sleep -Seconds 3
  & $adb @serialArg shell input keyevent 31   # AKEYCODE_C (down + up)
  Start-Sleep -Seconds 6

  $rec = Join-Path $here "recorded-input-app.txt"
  $log = & $adb @serialArg logcat -d -s "XIOM-A3:*"
  $log | Out-File -FilePath $rec -Encoding utf8
  $log | ForEach-Object { $_ }

  Add-Content -Path $rec -Value "`n== documented block: touch injection (dispatcher view of this window, captured live) =="
  $block | ForEach-Object { Add-Content -Path $rec -Value $_; $_ }
  $touchNote = & $adb @serialArg shell "input tap 540 1200; sleep 2; logcat -d -s 'XIOM-A3:*' | tail -1"
  Add-Content -Path $rec -Value "== post-tap app log tail (expected: unchanged -- no touch delivered) =="
  $touchNote | ForEach-Object { Add-Content -Path $rec -Value $_; $_ }

  if (-not ($log | Select-String -SimpleMatch "A3_ALL_EVIDENCE_COLLECTED" -Quiet)) { $appFail = 1 }
  if ($log | Select-String -SimpleMatch "A3_RESULT fail=0" -Quiet) { } else { $appFail = 1 }
  if ($log | Select-String -SimpleMatch "FAIL " -Quiet) { $appFail = 1 }

  & $adb @serialArg shell am force-stop com.xiom.inputprobe
  & $adb @serialArg uninstall com.xiom.inputprobe | Out-Null
  if ($appFail -ne 0) { Write-Host "app probe: FAIL (recorded to $rec)" } else { Write-Host "app probe: PASS (recorded to $rec)" }
}

if ($shellFail -ne 0 -or $appFail -ne 0) { exit 1 }
exit 0
