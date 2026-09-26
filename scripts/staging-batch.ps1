# XIOM -- staging canary batch runner for xiom-packages/packages
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Sequential, resumable staging canary runner for the frozen batch in
# docs/staging-batch.txt.
#
# Why sequential: the publish workflow has a repository-level concurrency
# group (`registry-publish`, cancel-in-progress: false). GitHub cancels any
# *pending* run when a newer run joins the same group, so bulk-dispatching
# the whole batch cancels everything except the first and last run. This
# runner therefore keeps at most one run `pending` and dispatches the next
# name only when the previous run has started.
#
# Safety:
#   * Dry run by default (lists the batch and the ledger).
#   * The registry must be the staging URL; production is refused.
#   * No tags, no batches, no production publishes.
#
# Usage (from the repo root):
#   .\scripts\staging-batch.ps1                    # dry run: batch + ledger
#   .\scripts\staging-batch.ps1 -Status            # live status summary
#   .\scripts\staging-batch.ps1 -Run               # run/resume the pipeline
#
# The ledger is docs/staging-batch-runs.txt (TSV: name, run id, state).
# States: queued, dispatched, waiting, approved, success, failed, cancelled.
# A run concluded `cancelled` is re-queued automatically (it never ran).

param(
  [switch]$Run,
  [switch]$Status,
  [string]$Registry = "https://staging.registry.xiom-lang.org",
  [string]$ListFile = "docs/staging-batch.txt",
  [string]$RunsFile = "docs/staging-batch-runs.txt",
  [int]$DispatchDelayMs = 1200,
  [int]$TickSeconds = 15,
  [int]$MaxRunMinutes = 360
)

$ErrorActionPreference = "Stop"
$repo = "xiom-packages/packages"
$workflow = "publish-registry.yml"

if ($Registry -notmatch "^https://staging\.registry\.xiom-lang\.org/?$") {
  throw "refusing to run: registry must be the staging URL (got '$Registry')"
}
if (-not (Test-Path -LiteralPath $ListFile)) { throw "batch list not found: $ListFile" }

$names = @(
  Get-Content -LiteralPath $ListFile |
    Where-Object { $_ -match "^xiom\.[a-z0-9._-]+$" }
)
if ($names.Count -eq 0) { throw "batch list is empty: $ListFile" }

# ---------------------------------------------------------------- ledger
function Read-Ledger {
  $ledger = @{}
  if (Test-Path -LiteralPath $RunsFile) {
    foreach ($line in (Get-Content -LiteralPath $RunsFile)) {
      if ($line -match "^xiom\.[a-z0-9._-]+\t") {
        $p = $line -split "`t"
        $ledger[$p[0]] = [pscustomobject]@{ RunId = [long]$p[1]; State = $p[2] }
      }
    }
  }
  return $ledger
}

function Write-Ledger {
  param($Ledger)
  $out = New-Object System.Collections.Generic.List[string]
  $out.Add("# name`trun_id`tstate`t(updated $(Get-Date -Format s))")
  foreach ($n in $names) {
    if ($Ledger.ContainsKey($n)) {
      $e = $Ledger[$n]
      $out.Add("$n`t$($e.RunId)`t$($e.State)")
    } else {
      $out.Add("$n`t0`tqueued")
    }
  }
  Set-Content -LiteralPath $RunsFile -Value $out -Encoding ASCII
}

# ---------------------------------------------------------------- gh helpers
function Get-LiveRuns {
  $json = & gh run list -R $repo --workflow $workflow --limit 300 `
    --json databaseId,status,conclusion 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $json) { return @{} }
  $map = @{}
  foreach ($r in ($json | ConvertFrom-Json)) {
    $map[[long]$r.databaseId] = [pscustomobject]@{
      Status = $r.status; Conclusion = $r.conclusion
    }
  }
  return $map
}

function Assert-No-Throttle {
  param([string]$Output)
  if ($Output -match "HTTP 403" -or $Output -match "HTTP 429" -or
      $Output -match "rate limit exceeded" -or $Output -match "secondary rate limit") {
    Set-Content -LiteralPath "docs/staging-batch-STOP.txt" `
      -Value "gh reported 403/429/rate-limit at $(Get-Date -Format s):`n$Output" -Encoding ASCII
    throw "throttle/auth error observed; see docs/staging-batch-STOP.txt"
  }
}

function Approve-Run {
  param([long]$RunId)
  $dep = & gh api "repos/$repo/actions/runs/$RunId/pending_deployments" 2>&1
  Assert-No-Throttle -Output ($dep -join "`n")
  if ($LASTEXITCODE -ne 0 -or -not $dep) { return 0 }
  $parsed = @($dep | ConvertFrom-Json)
  $n = 0
  foreach ($d in $parsed) {
    if (-not $d.current_user_can_approve) { continue }
    $envId = [long]$d.environment.id
    $body = @{
      state           = "approved"
      environment_ids = @($envId)
      comment         = "staging canary batch approved by the packages session"
    } | ConvertTo-Json -Compress
    $res = $body | & gh api --method POST "repos/$repo/actions/runs/$RunId/pending_deployments" --input - 2>&1
    Assert-No-Throttle -Output ($res -join "`n")
    if ($LASTEXITCODE -eq 0) {
      Write-Host "  approved run $RunId (env $envId)"
      $n = $n + 1
    } else {
      Write-Host "  approval failed for run $RunId: $res"
    }
  }
  return $n
}

function Invoke-Dispatch {
  param([string]$Package)
  $before = Get-LiveRuns
  $maxBefore = [long]0
  if ($before.Count -gt 0) {
    $maxBefore = ($before.Keys | Measure-Object -Maximum).Maximum
  }
  $out = & gh workflow run $workflow -R $repo -f "registry=$Registry" -f "package=$Package" 2>&1
  Assert-No-Throttle -Output ($out -join "`n")
  if ($LASTEXITCODE -ne 0) { throw "gh workflow run failed for $Package`: $out" }
  $runId = [long]0
  $waited = 0
  while ($runId -eq 0 -and $waited -lt 40) {
    Start-Sleep -Seconds 2
    $waited = $waited + 2
    $after = Get-LiveRuns
    $fresh = @($after.Keys | Where-Object { [long]$_ -gt $maxBefore })
    if ($fresh.Count -ge 1) {
      $runId = [long](($fresh | Measure-Object -Minimum).Minimum)
    }
  }
  if ($runId -eq 0) { throw "no run id observed for $Package after dispatch" }
  return $runId
}

# ---------------------------------------------------------------- dry run
$ledger = Read-Ledger
if (-not $Run) {
  $counts = @{}
  foreach ($n in $names) {
    $s = "queued"
    if ($ledger.ContainsKey($n)) { $s = $ledger[$n].State }
    $counts[$s] = 1 + $counts[$s]
  }
  Write-Host "staging batch: $($names.Count) packages -> $Registry"
  if ($ledger.Count -gt 0) {
    Write-Host "ledger states:"
    $counts.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }
  }
  if ($Status) {
    $live = Get-LiveRuns
    foreach ($n in $names) {
      if (-not $ledger.ContainsKey($n)) { continue }
      $e = $ledger[$n]
      $r = $live[$e.RunId]
      $ls = "?"
      if ($r) { $ls = "$($r.Status)/$($r.Conclusion)" }
      Write-Host ("  {0,-24} {1,-14} {2,-12} {3}" -f $n, $e.RunId, $e.State, $ls)
    }
  }
  Write-Host "pass -Run to execute/resume the sequential pipeline."
  exit 0
}

# ---------------------------------------------------------------- pipeline
Write-Host "staging pipeline start: $($names.Count) packages -> $Registry"
$deadline = (Get-Date).AddMinutes($MaxRunMinutes)
$dispatchDelayOk = $true

while ($true) {
  if ((Get-Date) -gt $deadline) { Write-Host "pipeline deadline reached"; break }
  $live = Get-LiveRuns
  $alive = @()
  $queued = @()
  foreach ($n in $names) {
    if (-not $ledger.ContainsKey($n)) { $queued += $n; continue }
    $e = $ledger[$n]
    if ($e.State -eq "success" -or $e.State -eq "failed") { continue }
    $r = $live[$e.RunId]
    if (-not $r) { $queued += $n; continue }
    if ($r.Status -eq "completed") {
      if ($r.Conclusion -eq "success") {
        $e.State = "success"
        Write-Host "OK   $n (run $($e.RunId))"
      } elseif ($r.Conclusion -eq "cancelled") {
        Write-Host "CANC $n (run $($e.RunId)) -> re-queued"
        $e.State = "queued"
        $queued += $n
      } else {
        $e.State = "failed"
        Write-Ledger -Ledger $ledger
        Write-Host "FAIL $n (run $($e.RunId)) conclusion=$($r.Conclusion)"
        exit 2
      }
      continue
    }
    $alive += [pscustomobject]@{ Name = $n; Entry = $e; Live = $r }
  }

  # approve every run that reached the deployment gate
  foreach ($a in $alive) {
    if ($a.Live.Status -eq "waiting") {
      $a.Entry.State = "waiting"
      $n = Approve-Run -RunId $a.Entry.RunId
      if ($n -gt 0) { $a.Entry.State = "approved" }
    } elseif ($a.Live.Status -eq "in_progress") {
      $a.Entry.State = "approved"
    }
  }
  Write-Ledger -Ledger $ledger

  $aliveCount = $alive.Count
  $pendingCount = @($alive | Where-Object { $_.Live.Status -eq "pending" }).Count
  $successCount = @($names | Where-Object { $ledger.ContainsKey($_) -and $ledger[$_].State -eq "success" }).Count
  $failedCount = @($names | Where-Object { $ledger.ContainsKey($_) -and $ledger[$_].State -eq "failed" }).Count

  if ($successCount -eq $names.Count) {
    Write-Host "pipeline complete: $successCount/$($names.Count) success"
    break
  }

  # dispatch policy: never create a second pending run
  if ($queued.Count -gt 0 -and $pendingCount -eq 0 -and $aliveCount -le 1) {
    $next = $queued[0]
    Write-Host "dispatch $next (alive=$aliveCount)"
    $runId = Invoke-Dispatch -Package $next
    $ledger[$next] = [pscustomobject]@{ RunId = $runId; State = "dispatched" }
    Write-Host "  -> run $runId"
    Write-Ledger -Ledger $ledger
    if ($DispatchDelayMs -gt 0) { Start-Sleep -Milliseconds $DispatchDelayMs }
    continue
  }

  $summary = "progress: success=$successCount/$($names.Count) alive=$aliveCount pending=$pendingCount queued=$($queued.Count) failed=$failedCount"
  Write-Host $summary
  Start-Sleep -Seconds $TickSeconds
}
Write-Ledger -Ledger $ledger
