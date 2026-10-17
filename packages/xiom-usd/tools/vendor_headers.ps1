# Vendor the OpenUSD header closure for xiom.usd.
#
# Maintainer tool (not used by the package build). It copies the transitive
# header closure of the bridge's includes from the pinned upstream clones,
# rewrites every vendored #include to an exact relative path (the XIOM link
# line has no -I passthrough; assimp's combine.py precedent), and records the
# generated headers.
#
# Usage:
#   .\tools\vendor_headers.ps1
#     -OpenUsd E:\repos\openusd
#     -Tbb     E:\repos\oneTBB
#
# Prerequisites (upstream-first doctrine): OpenUSD v26.08 at
# ee47c679abde5b467a7b6a41f3b2285564a4222e, oneTBB 2021.13 headers.
param(
    [string]$OpenUsd = "E:\repos\openusd",
    [string]$Tbb = "E:\repos\oneTBB",
    [string]$Clang = "C:\Program Files\LLVM\bin\clang++.exe"
)
$ErrorActionPreference = "Stop"
$pkg = Split-Path -Parent $PSScriptRoot
$inc = Join-Path $pkg "vendor\include"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("usd-vendor-" + [guid]::NewGuid().ToString("N"))
if (Test-Path -LiteralPath $inc) { Remove-Item -LiteralPath $inc -Recurse -Force }
New-Item -ItemType Directory -Force -Path $tmp, $inc | Out-Null

# --- 1. Generate pxr/pxr.h and pxr/base/work/impl.h (CMake-configured files).
$pxrIn = Join-Path $OpenUsd "pxr\pxr.h.in"
$pxrOut = Join-Path $inc "pxr\pxr.h"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pxrOut) | Out-Null
$t = Get-Content -LiteralPath $pxrIn -Raw
$t = $t.Replace('@PXR_MAJOR_VERSION@','0').Replace('@PXR_MINOR_VERSION@','26').Replace('@PXR_PATCH_VERSION@','8').
    Replace('@PXR_VERSION@','2608').Replace('@PXR_USE_NAMESPACES@','1').
    Replace('@PXR_EXTERNAL_NAMESPACE@','pxr').Replace('@PXR_INTERNAL_NAMESPACE@','pxrInternal_v0_26_8').
    Replace('@PXR_PYTHON_SUPPORT_ENABLED@','0').Replace('@PXR_PREFER_SAFETY_OVER_SPEED@','0').
    Replace('@PXR_ARCH_PREFER_TSC_TIMING@','0')
Set-Content -LiteralPath $pxrOut -Value $t -Encoding ASCII
$workIn = Join-Path $OpenUsd "pxr\base\work\impl.h.in"
$workOut = Join-Path $inc "pxr\base\work\impl.h"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $workOut) | Out-Null
$t = Get-Content -LiteralPath $workIn -Raw
$t = $t.Replace('@PXR_WORK_IMPL_HEADER@','"pxr/base/work/workTBB/impl.h"')
Set-Content -LiteralPath $workOut -Value $t -Encoding ASCII

# --- 2. Compute the transitive closure with the pinned headers.
$probe = Join-Path $tmp "closure.cpp"
@"
#include <pxr/pxr.h>
#include <pxr/usd/sdf/path.h>
#include <pxr/usd/sdf/pool.h>
#include <pxr/usd/usd/stage.h>
#include <pxr/usd/usd/prim.h>
#include <pxr/usd/usd/attribute.h>
#include <pxr/usd/usd/relationship.h>
#include <pxr/usd/usd/primRange.h>
#include <pxr/usd/usd/primFlags.h>
#include <pxr/base/vt/array.h>
#include <pxr/base/gf/vec3f.h>
#include <pxr/base/tf/token.h>
int main() { return 0; }
"@ | Set-Content -LiteralPath $probe -Encoding ASCII
$mm = (& $Clang -std=c++17 -MM -DPXR_STATIC -D_ITERATOR_DEBUG_LEVEL=0 -DNDEBUG -D__TBB_NO_IMPLICIT_LINKAGE=1 -I $OpenUsd -I (Join-Path $Tbb "include") $probe 2>$null | Out-String) -replace '/','\'
$paths = @()
foreach ($m in [regex]::Matches($mm, '[A-Za-z]:\\[^\s]+')) {
    $p = $m.Value.TrimEnd('\')
    if ($p -like "$OpenUsd*" -or $p -like "$Tbb*") { $paths += $p }
}
$paths = $paths | Sort-Object -Unique
Write-Host "closure: $($paths.Count) headers"

function Normalize-Rel([string]$p) {
    $parts = @()
    foreach ($seg in ($p -replace '\\','/' -split '/')) {
        if ($seg -eq '' -or $seg -eq '.') { continue }
        if ($seg -eq '..') { if ($parts.Count -eq 1) { $parts = @() } elseif ($parts.Count -gt 1) { $parts = $parts[0..($parts.Count-2)] }; continue }
        $parts += $seg
    }
    return ($parts -join '/')
}

# --- 3. Copy the closure, preserving the include-root-relative layout.
$copied = @{}
foreach ($src in $paths) {
    if ($src -like "$OpenUsd*") {
        $rel = $src.Substring($OpenUsd.Length).TrimStart('\')
    } else {
        $rel = $src.Substring($Tbb.Length).TrimStart('\')
        if ($rel -like "include\*") { $rel = $rel.Substring(8) } else { continue }
    }
    $rel = Normalize-Rel $rel
    $dst = Join-Path $inc ($rel -replace '/','\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $copied[$rel] = $true
}
Write-Host "copied: $($copied.Count) headers"

# --- 4. Rewrite vendored includes to exact relative paths.
$rewritten = 0
$missing = New-Object System.Collections.Generic.HashSet[string]
foreach ($rel in ($copied.Keys | Sort-Object)) {
    $file = Join-Path $inc ($rel -replace '/','\')
    $dir = Split-Path -Parent $file
    $lines = Get-Content -LiteralPath $file
    $outLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $m = [regex]::Match($line, '^(\s*#\s*include\s*)([<"])([^>"]+)([>"])')
        if ($m.Success) {
            $target = Normalize-Rel $m.Groups[3].Value
            if ($target.StartsWith("pxr/") -or $target.StartsWith("oneapi/") -or $target.StartsWith("tbb/")) {
                $targetFile = Join-Path $inc ($target -replace '/','\')
                if (Test-Path -LiteralPath $targetFile) {
                    $relPath = [System.IO.Path]::GetFullPath($targetFile).Substring([System.IO.Path]::GetFullPath($inc).TrimEnd('\').Length + 1) -replace '\\','/'
                    $from = [System.IO.Path]::GetFullPath($dir).Substring([System.IO.Path]::GetFullPath($inc).TrimEnd('\').Length + 1) -replace '\\','/'
                    $fromParts = if ($from) { $from -split '/' } else { @() }
                    $toParts = $relPath -split '/'
                    $i = 0
                    while ($i -lt $fromParts.Count -and $i -lt $toParts.Count -and $fromParts[$i] -eq $toParts[$i]) { $i++ }
                    $parts = @()
                    for ($j = $i; $j -lt $fromParts.Count; $j++) { $parts += ".." }
                    $parts += $toParts[$i..($toParts.Count-1)]
                    $newInc = ($parts -join '/')
                    $line = $m.Groups[1].Value + '"' + $newInc + '"'
                    $rewritten++
                } else {
                    [void]$missing.Add($target)
                }
            }
        }
        $outLines.Add($line)
    }
    [System.IO.File]::WriteAllLines($file, $outLines, (New-Object System.Text.UTF8Encoding($false)))
}
Write-Host "rewritten includes: $rewritten"
if ($missing.Count -gt 0) {
    Write-Host "not in closure (left unchanged): $($missing.Count)"
    $missing | Sort-Object | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
}

# --- 5. Licenses + manifest.
Copy-Item -LiteralPath (Join-Path $OpenUsd "LICENSE.txt") -Destination (Join-Path $pkg "vendor\LICENSE-OpenUSD.txt") -Force
Copy-Item -LiteralPath (Join-Path $OpenUsd "NOTICE.txt") -Destination (Join-Path $pkg "vendor\NOTICE-OpenUSD.txt") -Force
$tbbLicense = Join-Path $Tbb "LICENSE.txt"
if (Test-Path -LiteralPath $tbbLicense) {
    Copy-Item -LiteralPath $tbbLicense -Destination (Join-Path $pkg "vendor\LICENSE-oneTBB.txt") -Force
}
@"
Vendored header closure -- OpenUSD v26.08 (TOST-1.0, Apache-2.0 class)
+ oneTBB 2021.13 headers (Apache-2.0).
Generated by tools/vendor_headers.ps1. Includes are rewritten to exact
relative paths; no other edits. See PROVENANCE.md for the pin and terms.
Files: $((Get-ChildItem $inc -Recurse -File | Measure-Object).Count)
"@ | Set-Content -LiteralPath (Join-Path $pkg "vendor\README.md") -Encoding ASCII

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue




