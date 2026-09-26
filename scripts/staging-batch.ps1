# XIOM -- staging canary batch runner for xiom-packages/packages
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Dispatches the frozen staging canary batch (docs/staging-batch.txt) with
# `gh workflow run publish-registry.yml`, maps every dispatch to its run ID,
# and optionally approves the `registry-publish` environment gate for each
# run via the pending_deployments API.
#
# Safety:
#   * Dry run by default: nothing is dispatched without -Execute.
#   * The registry must be the staging URL; production is refused.
#   * No tags, no batches, no production publishes.
#
# Usage (from the repo root):
#   .\scripts\staging-batch.ps1                      # dry run: list the batch
#   .\scripts\staging-batch.ps1 -Execute             # dispatch all 130 names
#   .\scripts\staging-batch.ps1 -Approve             # one approval pass
#   .\scripts\staging-batch.ps1 -Approve -Watch      # approve until done
#
# -Execute writes docs/staging-batch-runs.txt (TSV: name, run id, status).

param(
  [switch]$Execute,
  [switch]$Approve,
  [switch]$Watch,
  [string]$Registry = "https://staging.registry.xiom-lang.org",
  [string]$ListFile = "docs/staging-batch.txt",
  [string]$RunsFile = "docs/staging-batch-runs.txt",
  [int]$DispatchDelayMs = 1200,
  [int]$MaxWatchMinutes = 120
)

$ErrorActionPreference = "Stop"
$repo = "xiom-packages/packages"
$workflow = "publish-registry.yml"

if ($Registry -notmatch "^https://staging\.registry\.xiom-lang\.org/?$") {
  throw "refusing to dispatch: registry must be the staging URL (got '$Registry')"
}

if (-not (Test-Path -LiteralPath $ListFile)) {
  throw "batch list not found: $ListFile"
}
$names = @(
  Get-Content -LiteralPath $ListFile |
    Where-Object { $_ -match "^xiom\.[a-z0-9._-]+$" }
)
if ($names.Count -eq 0) {
  throw "batch list is empty: $ListFile"
}

function Get-DispatchRuns {
  $json = & gh run list -R $repo --workflow $workflow --event workflow_dispatch `
    --limit 200 --json databaseId,status,conclusion,createdAt 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $json) { return @() }
  return @($json | ConvertFrom-Json | Sort-Object databaseId)
}

function Invoke-Dispatch {
  param([string]$Package)
  & gh workflow run $workflow -R $repo -f "registry=$Registry" -f "package=$Package" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "gh workflow run failed for $Package"
  }
}

# ---------------------------------------------------------------- dry run
if (-not $Execute -and -not $Approve) {
  Write-Host "staging batch (dry run): $($names.Count) packages -> $Registry"
  $names | ForEach-Object { Write-Host "  $_" }
  Write-Host "pass -Execute to dispatch, -Approve to handle the environment gate."
  exit 0
}

# ---------------------------------------------------------------- dispatch
if ($Execute) {
  Write-Host "dispatching $($names.Count) canaries to $Registry"
  $rows = New-Object System.Collections.Generic.List[string]
  $rows.Add("# name`trun_id`tstatus`t(dispatched $(Get-Date -Format s))")
  $i = 0
  foreach ($n in $names) {
    $i = $i + 1
    $before = Get-DispatchRuns
    $maxBefore = 0
    if ($before.Count -gt 0) { $maxBefore = [int]$before[-1].databaseId }
    Invoke-Dispatch -Package $n
    # wait for the new run to appear (creation is ordered by databaseId)
    $runId = 0
    $waited = 0
    while ($runId -eq 0 -and $waited -lt 30) {
      Start-Sleep -Seconds 2
      $waited = $waited + 2
      $after = Get-DispatchRuns
      $fresh = @($after | Where-Object { [int]$_.databaseId -gt $maxBefore })
      if ($fresh.Count -ge 1) { $runId = [int]$fresh[0].databaseId }
    }
    if ($runId -eq 0) {
      Write-Host ("[{0}/{1}] {2}: dispatched but no run id observed" -f $i, $names.Count, $n)
      $rows.Add("$n`tUNKNOWN`tpending")
    } else {
      Write-Host ("[{0}/{1}] {2} -> run {3}" -f $i, $names.Count, $n, $runId)
      $rows.Add("$n`t$runId`tpending")
    }
    if ($DispatchDelayMs -gt 0) { Start-Sleep -Milliseconds $DispatchDelayMs }
  }
  Set-Content -LiteralPath $RunsFile -Value $rows -Encoding ASCII
  Write-Host "wrote $RunsFile with $($rows.Count - 1) rows"
}

# ---------------------------------------------------------------- approvals
if ($Approve) {
  if (-not (Test-Path -LiteralPath $RunsFile)) {
    throw "run map not found: $RunsFile (run -Execute first)"
  }
  $deadline = (Get-Date).AddMinutes($MaxWatchMinutes)
  do {
    $entries = @(
      Get-Content -LiteralPath $RunsFile |
        Where-Object { $_ -match "^xiom\.[a-z0-9._-]+\t\d+\t" } |
        ForEach-Object {
          $p = $_ -split "`t"
          [pscustomobject]@{ Name = $p[0]; RunId = [int]$p[1]; Status = $p[2] }
        }
    )
    if ($entries.Count -eq 0) { throw "no dispatch rows in $RunsFile" }
    $runs = Get-DispatchRuns
    $byId = @{}
    foreach ($r in $runs) { $byId[[int]$r.databaseId] = $r }

    $pending = 0
    $approvedNow = 0
    foreach ($e in $entries) {
      $run = $byId[[int]$e.RunId]
      if (-not $run) { continue }
      if ($run.status -eq "completed") { continue }
      $pending = $pending + 1
      $dep = & gh api "repos/$repo/actions/runs/$($e.RunId)/pending_deployments" 2>$null
      if ($LASTEXITCODE -ne 0 -or -not $dep) { continue }
      $parsed = @($dep | ConvertFrom-Json)
      foreach ($d in $parsed) {
        if ($d.state -ne "pending") { continue }
        $envId = [int]$d.environment.id
        & gh api --method POST "repos/$repo/actions/runs/$($e.RunId)/pending_deployments" `
          -f "state=approved" -f "environment_ids[]=$envId" `
          -f "comment=staging canary batch approved by the packages session" | Out-Null
        if ($LASTEXITCODE -eq 0) {
          Write-Host "approved $($e.Name) (run $($e.RunId), env $envId)"
          $approvedNow = $approvedNow + 1
        } else {
          Write-Host "approval failed for $($e.Name) (run $($e.RunId))"
        }
      }
    }

    $remaining = @($entries | Where-Object {
        $r = $byId[[int]$_.RunId]
        $r -and $r.status -ne "completed"
      }).Count
    Write-Host ("approval pass: {0} approved, {1} runs not completed" -f $approvedNow, $remaining)

    if (-not $Watch) { break }
    if ($remaining -eq 0) { break }
    if ((Get-Date) -gt $deadline) { Write-Host "watch timeout reached"; break }
    Start-Sleep -Seconds 20
  } while ($true)
}
