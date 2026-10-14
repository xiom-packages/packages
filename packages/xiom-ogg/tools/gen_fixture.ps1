#!/usr/bin/env pwsh
# ============================================================================
# xiom.ogg -- regenerate tests/fixtures/tone.ogg with the committed
# fixture generator (tools/make_ogg_fixture.xi).
# ============================================================================
# Module resolution is package-scoped on v0.64.4, and the generator imports
# BOTH xiom.opus and xiom.ogg, so it must execute from `packages/` where
# both package trees are visible (see the header of make_ogg_fixture.xi).
#
# Usage:  .\tools\gen_fixture.ps1            (from packages/xiom-ogg)
# Exit code 0 = fixture regenerated (fixture generator returned 0).
# ============================================================================
$ErrorActionPreference = "Stop"
$pkgDir = Split-Path -Parent $PSScriptRoot
$packagesDir = Split-Path -Parent $pkgDir

. (Join-Path $packagesDir "..\scripts\xiom.ps1")
$tool = Resolve-XiomToolchain
if ($tool.Stdlib) { $env:XIOM_STDLIB = $tool.Stdlib }

$scratch = Join-Path $packagesDir ".gen_fixture.xi"
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "make_ogg_fixture.xi") -Destination $scratch -Force

Push-Location $packagesDir
try {
    $logFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ogg-fixture-" + [guid]::NewGuid().ToString("N") + ".log")
    # Native stderr (e.g. "  compiled: a.exe") turns into terminating
    # ErrorRecords with ErrorActionPreference=Stop; capture via cmd /c
    # redirection like scripts/port.ps1 does.
    $cmdline = '"' + $tool.Xiom + '" --run "' + $scratch + '"'
    foreach ($c in @(
        "xiom-ogg\src\ogg_bridge.c",
        "xiom-ogg\vendor\ogg\bitwise.c",
        "xiom-ogg\vendor\ogg\framing.c",
        "xiom-opus\src\opus_bridge.c",
        "xiom-opus\src\opus_vendor_celt.c",
        "xiom-opus\src\opus_vendor_silk.c",
        "xiom-opus\src\opus_vendor_silk_float.c",
        "xiom-opus\src\opus_vendor_src.c"
    )) {
        $cmdline = $cmdline + ' --c-source "' + (Join-Path $packagesDir $c) + '"'
    }
    $cmdline = $cmdline + ' --timeout 900 > "' + $logFile + '" 2>&1'
    cmd /c $cmdline
    $code = $LASTEXITCODE
    Get-Content -LiteralPath $logFile -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "warning\[W001\]|^\s+'" }
    Remove-Item -LiteralPath $logFile -ErrorAction SilentlyContinue
} finally {
    Pop-Location
    Remove-Item -LiteralPath $scratch -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $packagesDir "a.exe"), (Join-Path $packagesDir "a.exe.ll") -ErrorAction SilentlyContinue
}
exit $code
