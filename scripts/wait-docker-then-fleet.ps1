#!/usr/bin/env pwsh
# ============================================================================
# Wait for the Docker engine to come up, then run the arm64 fleet sweep.
# Each probe is bounded so a hung named pipe cannot stall the watcher.
# ============================================================================
param(
    [int]$MaxWaitMin = 90,
    [int]$PollSec = 30
)
$ErrorActionPreference = "Continue"
$deadline = (Get-Date).AddMinutes($MaxWaitMin)
while ((Get-Date) -lt $deadline) {
    $job = Start-Job -ScriptBlock { docker version --format "{{.Server.Version}}" 2>$null }
    $ok = $null
    if (Wait-Job $job -Timeout 15) {
        $out = Receive-Job $job -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -eq 0 -and $out) { $ok = ($out | Select-Object -First 1) }
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($ok) {
        Write-Output "docker engine up: $ok -- starting arm64 fleet sweep"
        & (Join-Path $PSScriptRoot "emulate-arm64-fleet.ps1")
        exit $LASTEXITCODE
    }
    Write-Output ("docker not ready at " + (Get-Date -Format o) + "; retrying in $PollSec s")
    Start-Sleep -Seconds $PollSec
}
Write-Output "timed out waiting for the docker engine"
exit 1
