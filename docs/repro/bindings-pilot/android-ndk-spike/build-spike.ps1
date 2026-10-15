#!/usr/bin/env pwsh
# Android NDK spike builder (W1) -- see README.md.
# Reproduces: libopus-x86_64.so, libopus-aarch64.so, opus_harness.
# Usage: pwsh build-spike.ps1 [-OutDir <path>]
param([string]$OutDir = "$env:TEMP\kilo\android-spike")

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# docs/repro/bindings-pilot/android-ndk-spike -> repo root
$repo = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))
$clang = "C:\Android\sdk\ndk\27.1.12297006\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe"
$src = Join-Path $repo "packages\xiom-opus\src"
$v = Join-Path $src "..\vendor\opus"

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$srcs = @(
    (Join-Path $src "opus_bridge.c"),
    (Join-Path $src "opus_vendor_celt.c"),
    (Join-Path $src "opus_vendor_silk.c"),
    (Join-Path $src "opus_vendor_silk_float.c"),
    (Join-Path $src "opus_vendor_src.c")
)
$inc = @("-I", $v, "-I", (Join-Path $v "float"), "-I", (Join-Path $v "fixed"))

& $clang --target=x86_64-linux-android26 -fPIC -shared -O2 @inc "-Wl,-soname,libopus.so" -lm -o (Join-Path $OutDir "libopus-x86_64.so") @srcs
if ($LASTEXITCODE -ne 0) { throw "x86_64 libopus.so build failed" }

& $clang --target=aarch64-linux-android26 -fPIC -shared -O2 @inc "-Wl,-soname,libopus.so" -lm -o (Join-Path $OutDir "libopus-aarch64.so") @srcs
if ($LASTEXITCODE -ne 0) { throw "aarch64 libopus.so build failed" }

& $clang --target=x86_64-linux-android26 -fPIE -pie -O2 -o (Join-Path $OutDir "opus_harness") (Join-Path $here "opus_harness.c") -ldl
if ($LASTEXITCODE -ne 0) { throw "harness build failed" }

Write-Host "artifacts in $OutDir"
