#!/usr/bin/env pwsh
# ============================================================================
# Deterministic fuzz/property harness runner (H3).
# See tests\probes\probe_fuzz.xi for the sections and env knobs.
#
# Usage: .\scripts\fuzz.ps1 [-TimeoutSec 600]
# Exit:  the probe's exit code (0 = green); 124 on watchdog timeout.
# ============================================================================
[CmdletBinding()]
param([int]$TimeoutSec = 600)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

& (Join-Path $PSScriptRoot "run.ps1") (Join-Path $repoRoot "tests\probes\probe_fuzz.xi") -TimeoutSec $TimeoutSec
exit $LASTEXITCODE
