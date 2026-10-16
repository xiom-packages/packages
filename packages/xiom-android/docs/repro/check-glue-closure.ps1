#!/usr/bin/env pwsh
# xiom.android -- native_app_glue import-closure check (W2c evidence).
#
# The NDK's native_app_glue C unit (sources/android/native_app_glue/
# android_native_app_glue.c, shipped in r27b) is the reference CONSUMER of
# the A2 lifecycle-glue surface.  It is not vendored; this script compiles
# it for both Android ABIs and proves that every symbol it leaves
# undefined is either
#   - declared in this package's export set (src/android_bridge.c), or
#   - a documented FUTURE-slice import (A3 input, A12 log), or
#   - bionic/compiler runtime.
# An UNKNOWN symbol fails the check.
#
# Usage: powershell -File check-glue-closure.ps1
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# packages/xiom-android/docs/repro -> repo root
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
$ndk = "C:\Android\sdk\ndk\27.1.12297006"
$clang = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
$nm = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-nm.exe"
$bridge = Join-Path $repo "packages\xiom-android\src\android_bridge.c"
$glueDir = Join-Path $ndk "sources\android\native_app_glue"
$out = Join-Path $env:TEMP "kilo\android-glue-closure"
New-Item -ItemType Directory -Path $out -Force | Out-Null

# 1. Declared export set: the quoted names of k_export_set[] in the bridge.
$declared = @(Select-String -Path $bridge -Pattern '^\s+"([A-Za-z_][A-Za-z0-9_]*)",\s*$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value })
if ($declared.Count -ne 117) {
    Write-Host "FAIL export-set extraction: got $($declared.Count) names, expected 117"
    exit 1
}

# 2. Documented non-package imports (observed, not assumed).
$futureInput = @(
    "AInputQueue_attachLooper", "AInputQueue_detachLooper", "AInputQueue_getEvent",
    "AInputQueue_preDispatchEvent", "AInputQueue_finishEvent", "AInputEvent_getType"
)
$futureLog = @("__android_log_print")
# The glue's contract with the CONSUMER app: the app defines this entry
# point (declared in android_native_app_glue.h).
$consumer = @("android_main")
$bionic = @(
    "abort", "calloc", "close", "free", "malloc", "memcpy", "memset", "pipe", "read",
    "write", "strerror", "__errno", "__stack_chk_fail", "__stack_chk_fail_local",
    "pthread_attr_init", "pthread_attr_setdetachstate", "pthread_cond_broadcast",
    "pthread_cond_destroy", "pthread_cond_init", "pthread_cond_wait",
    "pthread_create", "pthread_mutex_destroy", "pthread_mutex_init",
    "pthread_mutex_lock", "pthread_mutex_unlock"
)

# 3. Compile the glue for both ABIs and walk its undefined symbols.
$unknown = @()
$covered = 0
$future = 0
$runtime = 0
$consumerCount = 0
foreach ($target in @("x86_64-linux-android26", "aarch64-linux-android26")) {
    $obj = Join-Path $out "glue-$target.o"
    & $clang --target=$target -c -O2 -o $obj (Join-Path $glueDir "android_native_app_glue.c")
    if ($LASTEXITCODE -ne 0) { throw "glue compile failed for $target" }
    $undef = & $nm -u $obj | ForEach-Object {
        $t = ($_.Trim() -split '\s+')[-1] -replace '@@?.*$', ''
        if ($t) { $t }
    } | Sort-Object -Unique
    Write-Host "== ${target}: $($undef.Count) undefined symbols =="
    foreach ($s in $undef) {
        if ($declared -contains $s) {
            $covered++
            Write-Host "  covered   $s"
        } elseif ($futureInput -contains $s) {
            $future++
            Write-Host "  A3-input  $s (documented future slice)"
        } elseif ($futureLog -contains $s) {
            $future++
            Write-Host "  A12-log   $s (documented; live as xiom.android-sys)"
        } elseif ($consumer -contains $s) {
            $consumerCount++
            Write-Host "  consumer  $s (defined by the app; glue contract)"
        } elseif ($bionic -contains $s) {
            $runtime++
            Write-Host "  bionic    $s"
        } else {
            $unknown += $s
            Write-Host "  UNKNOWN   $s"
        }
    }
}

Write-Host "summary: covered=$covered future=$future consumer=$consumerCount bionic=$runtime unknown=$($unknown.Count)"
if ($unknown.Count -ne 0) {
    Write-Host "RESULT: FAIL (unclassified glue imports)"
    exit 1
}
Write-Host "RESULT: PASS (native_app_glue import closure inside xiom.android + documented slices)"
exit 0
