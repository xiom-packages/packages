<#
.SYNOPSIS
  BENCH-1: embedded cross-engine benchmark -- ORBITDB vs SQLite vs bbolt on
  identical YCSB-ish phases (docs/BENCH-1.md).

.DESCRIPTION
  Deterministic matrix: same op stream (LCG, seed 12345), same phases
  (load/read/update/scan/delete), same value bytes per mode. Each engine
  runs against a FRESH database. SQLite runs the same-pinned CLI (3.54.0,
  lane-local tools dir); bbolt runs bench/bbolt/bin/bbolt-bench.exe; ORBITDB
  runs tests/probes/probe_ycsb.xi (compiled once per invocation).

  Driver notes (documented in docs/BENCH-1.md):
  - SQLite read phase is ONE statement over a 50k-row VALUES CTE with a
    correlated subquery (n point lookups, no per-statement CLI overhead);
    load/update/delete/scan are per-statement (their engine cost dominates
    except in sync=0 rows -- CLI overhead is reported via the raw log).
  - ORBITDB vals=100 (typed rows) is point-ops only and batch must be 1.
  - bbolt Go bool flags use `-sync=` form.

.EXAMPLE
  scripts\bench_cross.ps1 -N 10000 -Vals 8 -Batch 1 -Sync 1
  scripts\bench_cross.ps1 -N 50000 -Vals 8 -Batch 100 -Sync 0 -Engines orbitdb,sqlite,bbolt
#>
param(
    [int]$N = 10000,
    [int]$Vals = 8,
    [int]$Batch = 1,
    [int]$Sync = 1,
    [string]$Engines = "orbitdb,sqlite,bbolt",
    [switch]$PointOnly,
    [int]$TimeoutSec = 1800
)

$ErrorActionPreference = "Continue"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot
. (Join-Path $PSScriptRoot "dev-env.ps1") | Out-Null
# dev-env.ps1 sets $ErrorActionPreference = "Stop"; native stderr via 2>&1
# would then terminate this script (NativeCommandError). We use Start-Process
# with file redirection for every native invocation (the run.ps1 pattern).
$ErrorActionPreference = "Continue"

if ($N -lt 200) { throw "N must be >= 200" }
if ($Vals -ne 8 -and $Vals -ne 100) { throw "Vals must be 8 or 100" }
if ($Batch -lt 1) { throw "Batch must be >= 1" }
if ($Vals -eq 100 -and $Batch -gt 1 -and $Engines -match "orbitdb") {
    throw "orbitdb typed rows (Vals=100) require Batch=1 -- exclude orbitdb or set -Batch 1"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = Join-Path $repoRoot "probe-logs"
$sqlDir = Join-Path $outDir "ycsb-sql"
New-Item -ItemType Directory -Force -Path $outDir, $sqlDir | Out-Null
$rawLog = Join-Path $outDir "bench-cross-$stamp.txt"

# --- tool resolution -------------------------------------------------------
$sqliteExe = Join-Path $env:LOCALAPPDATA "xiom-orbitdb-tools\sqlite\sqlite3.exe"
if (-not (Test-Path $sqliteExe)) { $sqliteExe = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Source }
if (-not $sqliteExe) { throw "sqlite3 not found (expected $env:LOCALAPPDATA\xiom-orbitdb-tools\sqlite\sqlite3.exe)" }
$bboltExe = Join-Path $repoRoot "bench\bbolt\bin\bbolt-bench.exe"
if (-not (Test-Path $bboltExe)) { throw "bbolt driver not built (bench\bbolt\bin\bbolt-bench.exe)" }

$scans = [int]($N / 100)
$deletes = [int]($N / 10)
$results = New-Object System.Collections.Generic.List[string]

function Write-Raw([string]$line) {
    Write-Host $line
    Add-Content -LiteralPath $rawLog -Value $line
}

# --- shared deterministic streams (same arithmetic everywhere) -------------
function Get-Lcg([long]$state) {
    return [long](($state * 1103515245 + 12345) % 2147483648)
}

function Get-ReadKeys([int]$count, [int]$n, [long]$seed) {
    $keys = New-Object System.Collections.Generic.List[long]
    $state = $seed
    for ($i = 0; $i -lt $count; $i++) {
        $state = Get-Lcg $state
        $keys.Add($state % $n)
    }
    return $keys
}

function New-ValueLiteral([int]$key, [int]$vals) {
    if ($vals -eq 8) { return "$($key * 7 + 1)" }
    $pad = "{0:D8}" -f $key
    return "'" + $pad + ("x" * 92) + "'"
}

$readKeys = Get-ReadKeys $N $N 12345
$updateKeys = Get-ReadKeys $N $N 12345
$deleteKeys = Get-ReadKeys $deletes $N 12345
$scanStarts = Get-ReadKeys $scans ($N - 100) 12345

# --- SQLite phase scripts --------------------------------------------------
function New-SqlitePhaseScript([string]$phase, [string]$db) {
    $file = Join-Path $sqlDir "sqlite-$phase-$stamp.sql"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(".output nul")
    [void]$sb.AppendLine("PRAGMA journal_mode=WAL;")
    if ($Sync -eq 1) { [void]$sb.AppendLine("PRAGMA synchronous=FULL;") }
    else { [void]$sb.AppendLine("PRAGMA synchronous=OFF;") }
    switch ($phase) {
        "load" {
            $col = if ($Vals -eq 8) { "INTEGER" } else { "TEXT" }
            [void]$sb.AppendLine("CREATE TABLE IF NOT EXISTS kv(k INTEGER PRIMARY KEY, v $col);")
            $i = 0
            while ($i -lt $N) {
                $hi = [Math]::Min($i + $Batch, $N)
                if ($Batch -gt 1) { [void]$sb.AppendLine("BEGIN;") }
                for ($k = $i; $k -lt $hi; $k++) {
                    [void]$sb.AppendLine("INSERT INTO kv(k, v) VALUES ($k, $(New-ValueLiteral $k $Vals));")
                }
                if ($Batch -gt 1) { [void]$sb.AppendLine("COMMIT;") }
                $i = $hi
            }
        }
        "read" {
            # ONE statement: n correlated point lookups over a VALUES CTE.
            $vals = ($readKeys | ForEach-Object { "($_)" }) -join ","
            [void]$sb.AppendLine("WITH ks(k) AS (VALUES $vals) SELECT (SELECT v FROM kv WHERE k = ks.k) FROM ks;")
        }
        "update" {
            $i = 0
            while ($i -lt $N) {
                $hi = [Math]::Min($i + $Batch, $N)
                if ($Batch -gt 1) { [void]$sb.AppendLine("BEGIN;") }
                for ($j = $i; $j -lt $hi; $j++) {
                    $k = $updateKeys[$j]
                    [void]$sb.AppendLine("UPDATE kv SET v = $(New-ValueLiteral $k $Vals) WHERE k = $k;")
                }
                if ($Batch -gt 1) { [void]$sb.AppendLine("COMMIT;") }
                $i = $hi
            }
        }
        "scan" {
            foreach ($start in $scanStarts) {
                $hi = $start + 100
                [void]$sb.AppendLine("SELECT count(*) FROM (SELECT k FROM kv WHERE k >= $start AND k < $hi ORDER BY k LIMIT 100);")
            }
        }
        "delete" {
            $i = 0
            while ($i -lt $deletes) {
                $hi = [Math]::Min($i + $Batch, $deletes)
                if ($Batch -gt 1) { [void]$sb.AppendLine("BEGIN;") }
                for ($j = $i; $j -lt $hi; $j++) {
                    [void]$sb.AppendLine("DELETE FROM kv WHERE k = $($deleteKeys[$j]);")
                }
                if ($Batch -gt 1) { [void]$sb.AppendLine("COMMIT;") }
                $i = $hi
            }
        }
    }
    [System.IO.File]::WriteAllText($file, $sb.ToString())
    return $file
}

function Invoke-SqlitePhase([string]$phase, [string]$db, [int]$ops) {
    $script = New-SqlitePhaseScript $phase $db
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $sqliteExe
    $psi.Arguments = "`"$db`" `".read $script`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $null = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    $sw.Stop()
    if ($p.ExitCode -ne 0) { throw "sqlite $phase failed (rc=$($p.ExitCode)): $err" }
    $ms = [int]$sw.ElapsedMilliseconds
    $speed = if ($ms -gt 0) { [int]($ops * 1000 / $ms) } else { 0 }
    $line = "ycsb sqlite $phase n=$ops ms=$ms ops_s=$speed"
    Write-Raw $line
    $results.Add($line)
}

# --- native runner helper (raw ProcessStartInfo; file-free, no stderr trap,
#     reliable ExitCode on PS 5.1 -- Start-Process -PassThru loses ExitCode
#     with redirects in this host) -------------------------------------------
function Invoke-NativeCapture([string]$exe, [string]$argLine, [int]$timeoutSec) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = $argLine
    $psi.WorkingDirectory = $repoRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $so = $p.StandardOutput.ReadToEndAsync()
    $se = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($timeoutSec * 1000)) {
        $p.Kill()
        throw "native timeout: $exe $argLine"
    }
    $p.WaitForExit()
    $stdout = @($so.Result -split "`r?`n" | Where-Object { $_ -ne "" })
    $stderr = @($se.Result -split "`r?`n" | Where-Object { $_ -ne "" })
    return @{ Lines = ($stdout + $stderr); ExitCode = $p.ExitCode }
}

# --- bbolt ----------------------------------------------------------------
function Invoke-Bbolt([string]$db, [int]$syncFlag) {
    $syncArg = if ($syncFlag -eq 1) { "-sync=true" } else { "-sync=false" }
    $args = "-file `"$db`" -n $N -valsize $Vals $syncArg -batch $Batch -phase all -seed 12345"
    $r = Invoke-NativeCapture $bboltExe $args $TimeoutSec
    if ($r.ExitCode -ne 0) { throw "bbolt failed (rc=$($r.ExitCode)): $($r.Lines -join ' | ')" }
    foreach ($ln in $r.Lines) {
        $s = "$ln"
        if ($s -match "^ycsb bbolt") { Write-Raw $s; $results.Add($s) }
    }
}

# --- orbitdb --------------------------------------------------------------
function Invoke-Orbitdb([string]$db) {
    $bin = Join-Path $outDir "ycsb-orbitdb-$stamp.bin.exe"
    $env:ORBITDB_YCSB_FILE = $db
    $env:ORBITDB_YCSB_N = "$N"
    $env:ORBITDB_YCSB_VALS = "$Vals"
    $env:ORBITDB_YCSB_SYNC = "$Sync"
    $env:ORBITDB_YCSB_BATCH = "$Batch"
    $env:ORBITDB_YCSB_PHASE = "all"
    # compile once and run (the --run pass uses the env set above)
    $r = Invoke-NativeCapture $env:XIOM_COMPILER "--run tests\probes\probe_ycsb.xi -o `"$bin`"" $TimeoutSec
    foreach ($ln in $r.Lines) {
        $s = "$ln"
        if ($s -match "^ycsb orbitdb") { Write-Raw $s; $results.Add($s) }
    }
    if (-not (Test-Path $bin)) { throw "orbitdb probe did not compile" }
    if ($results | Where-Object { $_ -match "^ycsb orbitdb done ok=1" }) { return }
    throw "orbitdb probe run failed (rc=$($r.ExitCode); no done ok=1 line)"
}

# --- matrix ---------------------------------------------------------------
$engineList = $Engines.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
Write-Raw "=== BENCH-1 cross-engine run $stamp | N=$N vals=$Vals batch=$Batch sync=$Sync ==="
Write-Raw "engines: $($engineList -join ', ') | sqlite: $sqliteExe | toolchain: $(& $env:XIOM_COMPILER --version | Select-Object -First 1)"

foreach ($engine in $engineList) {
    switch ($engine) {
        "orbitdb" {
            $db = Join-Path $outDir "ycsb-orbitdb-$stamp.wal"
            Remove-Item "$db*" -ErrorAction SilentlyContinue
            Invoke-Orbitdb $db
            Get-ChildItem "$db*" -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
        }
        "sqlite" {
            $db = Join-Path $outDir "ycsb-sqlite-$stamp.db"
            Remove-Item "$db*" -ErrorAction SilentlyContinue
            Invoke-SqlitePhase "load" $db $N
            Invoke-SqlitePhase "read" $db $N
            Invoke-SqlitePhase "update" $db $N
            if (-not $PointOnly) {
                Invoke-SqlitePhase "scan" $db $scans
                Invoke-SqlitePhase "delete" $db $deletes
            }
            $count = & $sqliteExe $db "SELECT count(*) FROM kv;" 2>$null
            $count = "$count".Trim()
            $expectedAfterDelete = $N - (($deleteKeys | Select-Object -Unique).Count)
            if ($PointOnly) { $expectedAfterDelete = $N }
            $ok = 0
            if ($count -eq "$expectedAfterDelete") { $ok = 1 }
            # distinct-delete parity: repeats in the stream leave more keys
            # behind -- both engines (and the orbitdb/bbolt verify) track the
            # same distinct set, so this is the exact expectation.
            $line = "ycsb sqlite verify count=$count ok=$ok (expected $expectedAfterDelete)"
            Write-Raw $line
            $results.Add($line)
            Remove-Item "$db*" -ErrorAction SilentlyContinue
        }
        "bbolt" {
            $db = Join-Path $outDir "ycsb-bbolt-$stamp.db"
            Remove-Item "$db*" -ErrorAction SilentlyContinue
            Invoke-Bbolt $db $Sync
            Remove-Item "$db*" -ErrorAction SilentlyContinue
        }
        default { throw "unknown engine: $engine" }
    }
}

Write-Raw ""
Write-Raw "=== summary (ops_s) ==="
$phases = @("load", "read", "update", "scan", "delete")
foreach ($engine in $engineList) {
    foreach ($phase in $phases) {
        foreach ($r in $results) {
            if ($r -match "^ycsb $engine $phase n=(\d+) ms=(\d+) ops_s=(\d+)") {
                Write-Raw ("{0,-8} {1,-7} n={2,-7} ms={3,-8} ops_s={4}" -f $engine, $phase, $Matches[1], $Matches[2], $Matches[3])
            }
        }
    }
}
Write-Raw ""
Write-Raw "raw log: $rawLog"
