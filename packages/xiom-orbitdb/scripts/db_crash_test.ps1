#!/usr/bin/env pwsh
# ============================================================================
# XIOM ORBITDB file-backed DB crash/recovery test (WAL-before-ack).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Drives tests\probes\probe_db_file.xi (five crash scenarios per run):
#   A. WAL-only: writer puts N keys, hard-kill, torn tail, reopen recovers N,
#      heal + put one more -> N+1.
#   B. snapshot-only: writer puts N keys + checkpoint, hard-kill before any
#      tail write, torn tail, reopen recovers N from the snapshot alone.
#   C. snapshot + tail: writer checkpoints after N, appends Tail more keys,
#      hard-kill mid-tail, reopen recovers N+Tail (snapshot + tail replay).
#   D. uncommitted txn: writer checkpoints a baseline of N keys, opens a
#      transaction writing Tx keys, hard-kill BEFORE commit; reopen must
#      recover exactly N keys (the txn is discarded).
#   E. committed txn: same, but the txn commits before the kill; reopen must
#      recover N+Tx keys (snapshot + committed txn).
# After every recovery the harness runs `qverify`: key-range + value-filter
# queries must return the correct values from the recovered tree.
#
# Usage: .\scripts\db_crash_test.ps1 [-Keys 20] [-Tail 3] [-Tx 5] [-TimeoutSec 90]
# Exit:  0 = green, 1 = failed.
# ============================================================================
[CmdletBinding()]
param(
    [int]$Keys = 20,
    [int]$Tail = 3,
    [int]$Tx = 5,
    [int]$TimeoutSec = 90
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot "probe-logs"
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

if (-not $env:XIOM_COMPILER -or -not (Test-Path -LiteralPath $env:XIOM_COMPILER)) {
    . (Join-Path $PSScriptRoot "dev-env.ps1")
    if (-not $env:XIOM_COMPILER) { throw "XIOM_COMPILER not resolved" }
}

$probe = Join-Path $repoRoot "tests\probes\probe_db_file.xi"
$walFile = Join-Path $logDir "crash-dbfile.wal"
Remove-Item -LiteralPath $walFile, "$walFile.snap" -Force -ErrorAction SilentlyContinue

$pass = 0; $fail = 0
function Check {
    param([string]$Name, [bool]$Ok)
    if ($Ok) { Write-Host "[PASS] $Name"; $script:pass++ }
    else { Write-Host "[FAIL] $Name"; $script:fail++ }
}

# Shared-read line reader for the WAL polls. Plain Get-Content opens the file
# WITHOUT delete sharing on Windows/DrvFs: while a poll read is in flight the
# writer's rename-durable WAL truncate (`MoveFileEx` over the segment) fails
# with a sharing violation, the truncate is best-effort by design (older
# records stay; recovery still gated by the snapshot checkpoint_lsn), so the
# poll then keeps observing the UNTRUNCATED line count and false-REDs
# (observed=28/30 vs the expected 6/8, 2026-10-15). Open with
# FileShare.ReadWrite|Delete so the publish can win.
function Read-WalLinesShared {
    param([string]$Path)
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
              [System.IO.FileAccess]::Read,
              ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    } catch { return @() }
    $lines = @()
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        while ($null -ne ($line = $sr.ReadLine())) {
            if ($line -ne "") { $lines += $line }
        }
    } catch { } finally { $fs.Close() }
    return $lines
}

function Invoke-DbMode {
    param([string]$Mode, [int]$N, [string]$LastKey = "", [string]$LastVal = "", [string]$Path = "")
    if (-not $Path) { $Path = $walFile }
    $env:ORBITDB_DB_FILE = $Path
    $env:ORBITDB_DB_MODE = $Mode
    $env:ORBITDB_DB_N = "$N"
    if ($LastKey) { $env:ORBITDB_DB_LAST_KEY = $LastKey } else { Remove-Item Env:ORBITDB_DB_LAST_KEY -ErrorAction SilentlyContinue }
    if ($LastVal) { $env:ORBITDB_DB_LAST_VAL = $LastVal } else { Remove-Item Env:ORBITDB_DB_LAST_VAL -ErrorAction SilentlyContinue }
    & (Join-Path $PSScriptRoot "run.ps1") $probe -TimeoutSec 180 -Quiet | Out-Null
    return $LASTEXITCODE
}

function Start-Writer {
    param([string]$Mode, [int]$N, [int]$T, [string]$OutName, [string]$Path)
    $env:ORBITDB_DB_FILE = $Path
    $env:ORBITDB_DB_MODE = $Mode
    $env:ORBITDB_DB_N = "$N"
    $env:ORBITDB_DB_TAIL = "$T"
    $out = Join-Path $logDir "$OutName.out"
    $err = Join-Path $logDir "$OutName.err"
    # Unique output binary per writer (S4 harness hardening: sharing a.exe in
    # the repo root collides on DrvFs with a lingering killed image).
    $bin = Join-Path $logDir "$OutName-$PID.bin.exe"
    return Start-Process -FilePath $env:XIOM_COMPILER -ArgumentList @("--run", $probe, "-o", $bin) `
        -WorkingDirectory $repoRoot -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
}

# Idempotent upsert step (key 9999): retry ONCE on a nonzero exit. On a
# shared, loaded host a transient IO failure on the post-heal append happens
# (observed 2026-10-15 while other lanes compiled on the same machine; the
# same shape passed 20/20 in isolation). A persistent failure still REDs.
function Invoke-Put1 {
    param([int]$N, [string]$Path = "")
    if (-not $Path) { $Path = $walFile }
    $env:ORBITDB_DB_FILE = $Path
    $env:ORBITDB_DB_MODE = "put1"
    $env:ORBITDB_DB_N = "$N"
    Remove-Item Env:ORBITDB_DB_LAST_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:ORBITDB_DB_LAST_VAL -ErrorAction SilentlyContinue
    $rc = 1
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        & (Join-Path $PSScriptRoot "run.ps1") $probe -TimeoutSec 180 | Out-Null
        $rc = $LASTEXITCODE
        if ($rc -eq 0) {
            if ($attempt -eq 2) { Write-Host "[WARN] put1 transient failure absorbed by retry" }
            return 0
        }
        if ($attempt -eq 1) { Write-Host "[WARN] put1 attempt 1 rc=$rc; retrying once" }
    }
    return $rc
}

function Stop-Writer {
    param([System.Diagnostics.Process]$Writer)
    if (-not $Writer.HasExited) {
        try { & taskkill /T /F /PID $Writer.Id | Out-Null } catch { }
        $Writer.WaitForExit(10000) | Out-Null
    }
}

# Wait until the snapshot file exists and the WAL holds exactly ExpectedLines
# non-empty records (the writer hangs after that point). Returns the observed
# line count (-1 when the wait timed out or the writer exited early).
function Wait-ForCkptPoint {
    param([System.Diagnostics.Process]$Writer, [string]$Path, [string]$SnapPath,
          [int]$ExpectedLines, [int]$TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $observed = -1
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path -LiteralPath $SnapPath) -and (Test-Path -LiteralPath $Path)) {
            $observed = @(Read-WalLinesShared -Path $Path).Count
            if ($observed -eq $ExpectedLines) { break }
        }
        if ($Writer.HasExited) { break }
        Start-Sleep -Milliseconds 300
    }
    return $observed
}

# --- scenario A / phase 1: writer puts Keys records, then hangs -------------
$writer = Start-Writer -Mode "write" -N $Keys -T 0 -OutName "dbfile-writer" -Path $walFile

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$observed = 0
while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $walFile) {
        $observed = @(Read-WalLinesShared -Path $walFile).Count
        if ($observed -ge $Keys) { break }
    }
    if ($writer.HasExited) { break }
    Start-Sleep -Milliseconds 300
}
Check "writer put $Keys keys (observed=$observed)" ($observed -ge $Keys)

# --- phase 2: hard-kill + torn tail ----------------------------------------
Stop-Writer -Writer $writer
Add-Content -LiteralPath $walFile -Value "torn|" -NoNewline
Write-Host ("crash: killed writer, segment={0} bytes, torn tail appended" -f (Get-Item -LiteralPath $walFile).Length)

# --- phase 3: reopen, replay must recover exactly Keys keys ----------------
$rc = Invoke-DbMode -Mode "verify" -N $Keys
Check "reopen recovers $Keys keys (WAL replay, torn skipped)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "qverify" -N $Keys
Check "query after WAL replay: range + filter correct" ($rc -eq 0)

# --- phase 4: heal + put one more key --------------------------------------
$rc = Invoke-Put1 -N $Keys
Check "put after torn tail heals (put1 exit 0)" ($rc -eq 0)

# --- phase 5: N+1 and last-key integrity ------------------------------------
$rc = Invoke-DbMode -Mode "verify" -N ($Keys + 1) -LastKey "9999" -LastVal "99990"
Check "reopen recovers $($Keys + 1) keys incl. healed put" ($rc -eq 0)

# --- scenario B: checkpoint, kill before any tail (snapshot-only recovery) --
$ckptWal = Join-Path $logDir "crash-dbfile-ckpt.wal"
$ckptSnap = "$ckptWal.snap"
Remove-Item -LiteralPath $ckptWal, $ckptSnap -Force -ErrorAction SilentlyContinue
$writer = Start-Writer -Mode "ckpt" -N $Keys -T 0 -OutName "dbfile-writer-ckpt" -Path $ckptWal
$observed = Wait-ForCkptPoint -Writer $writer -Path $ckptWal -SnapPath $ckptSnap `
    -ExpectedLines 1 -TimeoutSec $TimeoutSec
Check "ckpt writer reached snapshot-only point (observed=$observed)" ($observed -eq 1)
Stop-Writer -Writer $writer
Add-Content -LiteralPath $ckptWal -Value "torn|" -NoNewline

$rc = Invoke-DbMode -Mode "verify" -N $Keys -Path $ckptWal
Check "ckpt reopen recovers $Keys keys from snapshot alone (torn ignored)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "qverify" -N $Keys -Path $ckptWal
Check "query after snapshot-only recovery: range + filter correct" ($rc -eq 0)
$rc = Invoke-Put1 -N $Keys -Path $ckptWal
Check "ckpt put after snapshot recovery heals tail (put1 exit 0)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "verify" -N ($Keys + 1) -LastKey "9999" -LastVal "99990" -Path $ckptWal
Check "ckpt reopen recovers $($Keys + 1) keys incl. healed put" ($rc -eq 0)

# --- scenario C: checkpoint + tail, kill mid-tail (snapshot + tail replay) --
$tailWal = Join-Path $logDir "crash-dbfile-tail.wal"
$tailSnap = "$tailWal.snap"
Remove-Item -LiteralPath $tailWal, $tailSnap -Force -ErrorAction SilentlyContinue
$writer = Start-Writer -Mode "ckpt" -N $Keys -T $Tail -OutName "dbfile-writer-tail" -Path $tailWal
$observed = Wait-ForCkptPoint -Writer $writer -Path $tailWal -SnapPath $tailSnap `
    -ExpectedLines (1 + $Tail) -TimeoutSec $TimeoutSec
Check "ckpt+tail writer wrote snapshot + $Tail tail keys (observed=$observed)" ($observed -eq (1 + $Tail))
Stop-Writer -Writer $writer
Add-Content -LiteralPath $tailWal -Value "torn|" -NoNewline

$rc = Invoke-DbMode -Mode "verify" -N ($Keys + $Tail) -Path $tailWal
Check "ckpt+tail reopen recovers $($Keys + $Tail) keys (snapshot + tail replay)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "qverify" -N ($Keys + $Tail) -Path $tailWal
Check "query after snapshot+tail recovery: range + filter correct" ($rc -eq 0)
$rc = Invoke-Put1 -N ($Keys + $Tail) -Path $tailWal
Check "ckpt+tail put after recovery heals tail (put1 exit 0)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "verify" -N ($Keys + $Tail + 1) -LastKey "9999" -LastVal "99990" -Path $tailWal
Check "ckpt+tail reopen recovers $($Keys + $Tail + 1) keys incl. healed put" ($rc -eq 0)

# --- scenario D: uncommitted txn discarded on kill --------------------------
$txnWal = Join-Path $logDir "crash-dbfile-txn.wal"
$txnSnap = "$txnWal.snap"
Remove-Item -LiteralPath $txnWal, $txnSnap -Force -ErrorAction SilentlyContinue
$env:ORBITDB_DB_TXN_COUNT = "$Tx"
$env:ORBITDB_DB_TXN_COMMIT = "0"
$writer = Start-Writer -Mode "txn" -N $Keys -T 0 -OutName "dbfile-writer-txn" -Path $txnWal
$observed = Wait-ForCkptPoint -Writer $writer -Path $txnWal -SnapPath $txnSnap `
    -ExpectedLines ($Tx + 2) -TimeoutSec $TimeoutSec
Check "txn writer reached pending-txn point (observed=$observed)" ($observed -eq ($Tx + 2))
Stop-Writer -Writer $writer
Add-Content -LiteralPath $txnWal -Value "torn|" -NoNewline

$rc = Invoke-DbMode -Mode "verify" -N $Keys -Path $txnWal
Check "uncommitted txn discarded: $Keys keys recovered (no txn keys)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "qverify" -N $Keys -Path $txnWal
Check "query after uncommitted-txn recovery: range + filter correct" ($rc -eq 0)
$rc = Invoke-Put1 -N $Keys -Path $txnWal
Check "put after uncommitted-txn recovery heals WAL (put1 exit 0)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "verify" -N ($Keys + 1) -LastKey "9999" -LastVal "99990" -Path $txnWal
Check "reopen recovers $($Keys + 1) keys incl. healed put" ($rc -eq 0)

# --- scenario E: committed txn recovered on kill ----------------------------
$txncWal = Join-Path $logDir "crash-dbfile-txn2.wal"
$txncSnap = "$txncWal.snap"
Remove-Item -LiteralPath $txncWal, $txncSnap -Force -ErrorAction SilentlyContinue
$env:ORBITDB_DB_TXN_COUNT = "$Tx"
$env:ORBITDB_DB_TXN_COMMIT = "1"
$writer = Start-Writer -Mode "txn" -N $Keys -T 0 -OutName "dbfile-writer-txn2" -Path $txncWal
$observed = Wait-ForCkptPoint -Writer $writer -Path $txncWal -SnapPath $txncSnap `
    -ExpectedLines ($Tx + 3) -TimeoutSec $TimeoutSec
Check "txn writer reached committed point (observed=$observed)" ($observed -eq ($Tx + 3))
Stop-Writer -Writer $writer
Add-Content -LiteralPath $txncWal -Value "torn|" -NoNewline

$rc = Invoke-DbMode -Mode "verify" -N ($Keys + $Tx) -Path $txncWal
Check "committed txn recovered: $($Keys + $Tx) keys (snapshot + txn)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "qverify" -N ($Keys + $Tx) -Path $txncWal
Check "query after committed-txn recovery: range + filter correct" ($rc -eq 0)
$rc = Invoke-Put1 -N ($Keys + $Tx) -Path $txncWal
Check "put after committed-txn recovery heals WAL (put1 exit 0)" ($rc -eq 0)
$rc = Invoke-DbMode -Mode "verify" -N ($Keys + $Tx + 1) -LastKey "9999" -LastVal "99990" -Path $txncWal
Check "reopen recovers $($Keys + $Tx + 1) keys incl. healed put" ($rc -eq 0)

Write-Host ("crash: pass={0} fail={1}" -f $pass, $fail)
if ($fail -eq 0) { Write-Host "db-crash: GREEN"; exit 0 }
Write-Host "db-crash: RED"
exit 1
