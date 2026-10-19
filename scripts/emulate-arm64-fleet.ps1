#!/usr/bin/env pwsh
# ============================================================================
# arm64 fleet sweep -- run a set of package suites under arm64 emulation
# sequentially, writing per-package logs + a summary. Slow by nature
# (qemu-backed clang); designed to run as a background process.
# ============================================================================
param(
    [string[]]$Packages = @("serial","mqtt","i2c","spi","adc","pwm","sensor","can","ble","zigbee","hid","usb","modbus"),
    [string]$OutDir = "C:\Users\lefte\AppData\Local\Temp\kilo\arm64-fleet",
    [string]$Image = "xiom-arm64-emu:trixie"
)
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$root = Split-Path -Parent $PSScriptRoot
$harness = Join-Path $PSScriptRoot "emulate-arm64.ps1"
$summary = @()
foreach ($p in $Packages) {
    $suite = Join-Path $root ("packages\xiom-{0}\tests\test_conformance.xi" -f $p)
    if (-not (Test-Path -LiteralPath $suite)) {
        Write-Output "${p}: MISSING"
        $summary += ("{0}: MISSING" -f $p)
        continue
    }
    $log = Join-Path $OutDir ("{0}.log" -f $p)
    Write-Output "${p}: running (arm64 emulation) ..."
    & $harness -Package $p -Image $Image *> $log
    $rc = $LASTEXITCODE
    $verdict = (Select-String -Path $log -Pattern "all tests passed|suite green|FAIL" |
        Select-Object -Last 1).Line
    if ($verdict) { $verdict = $verdict.Trim() }
    $line = ("{0}: rc={1} {2}" -f $p, $rc, $verdict)
    Write-Output $line
    $summary += $line
}
$summary | Set-Content -Path (Join-Path $OutDir "summary.txt")
Write-Output "=== summary ==="
$summary
