#!/usr/bin/env bash
# BENCH-1: embedded cross-engine benchmark (WSL twin of scripts/bench_cross.ps1).
# ORBITDB vs SQLite vs bbolt on identical YCSB-ish phases -- see docs/BENCH-1.md.
#
# Usage: scripts/bench_cross.sh [-n N] [--vals 8|100] [--batch B] [--sync S]
#                              [--engines orbitdb,sqlite,bbolt] [--point-only]
#
# Same deterministic streams as the .ps1 twin and the drivers: LCG with
# multiplier 1103515245, increment 12345, modulus 2147483648, seed 12345.
# SQLite = ~/.local/bin/sqlite3 (pinned 3.54.0); bbolt =
# bench/bbolt/bin/bbolt-bench-linux-amd64; ORBITDB = tests/probes/probe_ycsb.xi.
# Databases live under /tmp (DrvFs-free) per the bench convention.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
. "$SCRIPT_DIR/dev-env.sh"

# BENCH-1 baseline: the STOCK release pin (bundled stdlib/runtime) is the
# right baseline for cross-engine numbers. Set BENCH_STOCK_STDLIB=1 to drop
# the lane-checkout stdlib. The 2026-10-16 Linux-compile WIP in the checkout
# (TCP_NODELAY include) is FIXED -- a451349, in 6c96bbb; a consumer compile
# on the checkout was verified green 2026-10-16 -- so the switch is the
# stock-baseline option, no longer a requirement.
if [ "${BENCH_STOCK_STDLIB:-0}" = "1" ]; then
  unset XIOM_STDLIB
fi

N=10000
VALS=8
BATCH=1
SYNC=1
ENGINES="orbitdb,sqlite,bbolt"
POINT_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--n) N=${2:?missing value}; shift 2 ;;
    --vals) VALS=${2:?missing value}; shift 2 ;;
    --batch) BATCH=${2:?missing value}; shift 2 ;;
    --sync) SYNC=${2:?missing value}; shift 2 ;;
    --engines) ENGINES=${2:?missing value}; shift 2 ;;
    --point-only) POINT_ONLY=1; shift ;;
    -h|--help) printf 'Usage: bench_cross.sh [-n N] [--vals 8|100] [--batch B] [--sync S] [--engines list] [--point-only]\n'; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

SQLITE="${HOME}/.local/bin/sqlite3"
[ -x "$SQLITE" ] || SQLITE="$(command -v sqlite3 || true)"
[ -n "$SQLITE" ] && [ -x "$SQLITE" ] || { printf 'sqlite3 not found (~/.local/bin/sqlite3)\n' >&2; exit 2; }
BBOLT="$REPO_ROOT/bench/bbolt/bin/bbolt-bench-linux-amd64"
[ -x "$BBOLT" ] || { printf 'bbolt linux driver missing: %s\n' "$BBOLT" >&2; exit 2; }

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$REPO_ROOT/probe-logs"
SQL_DIR="$OUT_DIR/ycsb-sql"
TMP_DIR="${TMPDIR:-/tmp}/orbitdb-ycsb-$STAMP"
mkdir -p "$OUT_DIR" "$SQL_DIR" "$TMP_DIR"
RAW="$OUT_DIR/bench-cross-wsl-$STAMP.txt"
SCANS=$((N / 100))
DELETES=$((N / 10))

raw() { printf '%s\n' "$1" | tee -a "$RAW"; }

now_ms() { date +%s%N | cut -b1-13; }   # epoch ms (nanosecond clock, ms precision)

# LCG: identical arithmetic to the .ps1 twin / drivers.
lcg() { # state n -> "state key" via globals STATE / KEY
  STATE=$(( (STATE * 1103515245 + 12345) % 2147483648 ))
  KEY=$(( STATE % $2 ))
}

value_literal() { # key vals -> SQL literal
  local k=$1 vals=$2
  if [ "$vals" -eq 8 ]; then printf '%d' $(( k * 7 + 1 )); return; fi
  printf "'%08d" "$k"; printf 'x%.0s' $(seq 1 92); printf "'"
}

# ---- streams ---------------------------------------------------------------
declare -a RK UK DK SK
STATE=12345
for ((i = 0; i < N; i++)); do lcg "$STATE" "$N"; RK[i]=$KEY; done
STATE=12345
for ((i = 0; i < N; i++)); do lcg "$STATE" "$N"; UK[i]=$KEY; done
STATE=12345
for ((i = 0; i < DELETES; i++)); do lcg "$STATE" "$N"; DK[i]=$KEY; done
STATE=12345
for ((i = 0; i < SCANS; i++)); do lcg "$STATE" "$((N - 100))"; SK[i]=$KEY; done

# distinct deletes (for verify parity with the drivers)
DISTINCT_DELETES=0
declare -A DMARK
for ((i = 0; i < DELETES; i++)); do
  if [ -z "${DMARK[${DK[$i]}]:-}" ]; then DMARK[${DK[$i]}]=1; DISTINCT_DELETES=$((DISTINCT_DELETES + 1)); fi
done

# ---- SQLite ----------------------------------------------------------------
sqlite_head() {
  printf '.output /dev/null\n'
  printf 'PRAGMA journal_mode=WAL;\n'
  if [ "$SYNC" -eq 1 ]; then printf 'PRAGMA synchronous=FULL;\n'; else printf 'PRAGMA synchronous=OFF;\n'; fi
}

sqlite_run_phase() { # phase db ops
  local phase=$1 db=$2 ops=$3
  local file="$SQL_DIR/sqlite-$phase-$STAMP.sql"
  {
    sqlite_head
    case "$phase" in
      load)
        local col="INTEGER"; [ "$VALS" -eq 100 ] && col="TEXT"
        printf 'CREATE TABLE IF NOT EXISTS kv(k INTEGER PRIMARY KEY, v %s);\n' "$col"
        local i hi k
        for ((i = 0; i < N; i += BATCH)); do
          hi=$((i + BATCH)); [ "$hi" -gt "$N" ] && hi=$N
          [ "$BATCH" -gt 1 ] && printf 'BEGIN;\n'
          for ((k = i; k < hi; k++)); do
            printf 'INSERT INTO kv(k, v) VALUES (%d, %s);\n' "$k" "$(value_literal "$k" "$VALS")"
          done
          [ "$BATCH" -gt 1 ] && printf 'COMMIT;\n'
        done
        ;;
      read)
        printf 'WITH ks(k) AS (VALUES '
        local first=1 k
        for ((k = 0; k < N; k++)); do
          [ $first -eq 0 ] && printf ','
          first=0
          printf '(%d)' "${RK[$k]}"
        done
        printf ') SELECT (SELECT v FROM kv WHERE k = ks.k) FROM ks;\n'
        ;;
      update)
        local i hi j k
        for ((i = 0; i < N; i += BATCH)); do
          hi=$((i + BATCH)); [ "$hi" -gt "$N" ] && hi=$N
          [ "$BATCH" -gt 1 ] && printf 'BEGIN;\n'
          for ((j = i; j < hi; j++)); do
            k=${UK[$j]}
            printf 'UPDATE kv SET v = %s WHERE k = %d;\n' "$(value_literal "$k" "$VALS")" "$k"
          done
          [ "$BATCH" -gt 1 ] && printf 'COMMIT;\n'
        done
        ;;
      scan)
        local s hi
        for ((s = 0; s < SCANS; s++)); do
          hi=$((${SK[$s]} + 100))
          printf 'SELECT count(*) FROM (SELECT k FROM kv WHERE k >= %d AND k < %d ORDER BY k LIMIT 100);\n' "${SK[$s]}" "$hi"
        done
        ;;
      delete)
        local i hi j
        for ((i = 0; i < DELETES; i += BATCH)); do
          hi=$((i + BATCH)); [ "$hi" -gt "$DELETES" ] && hi=$DELETES
          [ "$BATCH" -gt 1 ] && printf 'BEGIN;\n'
          for ((j = i; j < hi; j++)); do
            printf 'DELETE FROM kv WHERE k = %d;\n' "${DK[$j]}"
          done
          [ "$BATCH" -gt 1 ] && printf 'COMMIT;\n'
        done
        ;;
    esac
  } > "$file"
  local t0 t1 ms speed
  t0=$(now_ms)
  "$SQLITE" "$db" ".read $file" >/dev/null 2>&1 || { printf 'sqlite %s failed\n' "$phase" >&2; exit 1; }
  t1=$(now_ms)
  ms=$((t1 - t0)); speed=0
  [ "$ms" -gt 0 ] && speed=$((ops * 1000 / ms))
  raw "ycsb sqlite $phase n=$ops ms=$ms ops_s=$speed"
}

run_sqlite() {
  local db="$TMP_DIR/ycsb-sqlite.db"
  rm -f "$db" "$db-wal" "$db-shm"
  sqlite_run_phase load "$db" "$N"
  sqlite_run_phase read "$db" "$N"
  sqlite_run_phase update "$db" "$N"
  if [ "$POINT_ONLY" -eq 0 ]; then
    sqlite_run_phase scan "$db" "$SCANS"
    sqlite_run_phase delete "$db" "$DELETES"
  fi
  local count expected ok
  count=$("$SQLITE" "$db" "SELECT count(*) FROM kv;" | tr -d '[:space:]')
  expected=$N
  [ "$POINT_ONLY" -eq 0 ] && expected=$((N - DISTINCT_DELETES))
  ok=0; [ "$count" = "$expected" ] && ok=1
  raw "ycsb sqlite verify count=$count ok=$ok (expected $expected)"
  rm -f "$db" "$db-wal" "$db-shm"
}

# ---- bbolt -----------------------------------------------------------------
run_bbolt() {
  local db="$TMP_DIR/ycsb-bbolt.db"
  rm -f "$db"
  local syncarg="-sync=true"; [ "$SYNC" -eq 0 ] && syncarg="-sync=false"
  local out="$TMP_DIR/bbolt-out.txt"
  "$BBOLT" -file "$db" -n "$N" -valsize "$VALS" "$syncarg" -batch "$BATCH" -phase all -seed 12345 \
    >"$out" 2>&1
  local rc=$?
  grep -E '^ycsb bbolt' "$out" | while IFS= read -r line; do raw "$line"; done
  if [ "$rc" -ne 0 ] || ! grep -q '^ycsb bbolt done ok=1' "$out"; then
    printf 'bbolt failed (rc=%s):\n' "$rc" >&2; cat "$out" >&2; exit 1
  fi
  rm -f "$db"
}

# ---- orbitdb ---------------------------------------------------------------
run_orbitdb() {
  local db="$TMP_DIR/ycsb-orbitdb.wal"
  rm -f "$db"*
  local bin="$TMP_DIR/ycsb-orbitdb.bin"
  export ORBITDB_YCSB_FILE="$db"
  export ORBITDB_YCSB_N="$N"
  export ORBITDB_YCSB_VALS="$VALS"
  export ORBITDB_YCSB_SYNC="$SYNC"
  export ORBITDB_YCSB_BATCH="$BATCH"
  export ORBITDB_YCSB_PHASE="all"
  local out="$TMP_DIR/orbitdb-out.txt"
  "$XIOM_COMPILER" --run tests/probes/probe_ycsb.xi -o "$bin" >"$out" 2>&1
  grep -E '^ycsb orbitdb' "$out" | while IFS= read -r line; do raw "$line"; done
  if ! grep -q '^ycsb orbitdb done ok=1' "$out"; then
    printf 'orbitdb probe failed:\n' >&2; cat "$out" >&2; exit 1
  fi
  rm -f "$db" "$bin"
}

raw "=== BENCH-1 cross-engine run (WSL) $STAMP | N=$N vals=$VALS batch=$BATCH sync=$SYNC ==="
raw "engines: $ENGINES | sqlite: $SQLITE | toolchain: $($XIOM_COMPILER --version | head -n 1)"

IFS=',' read -r -a ENGINE_LIST <<< "$ENGINES"
for engine in "${ENGINE_LIST[@]}"; do
  case "$engine" in
    orbitdb) run_orbitdb ;;
    sqlite) run_sqlite ;;
    bbolt) run_bbolt ;;
    *) printf 'unknown engine: %s\n' "$engine" >&2; exit 2 ;;
  esac
done

raw ""
raw "=== summary (ops_s, engine/phase) ==="
grep -E '^ycsb (orbitdb|sqlite|bbolt) (load|read|update|scan|delete) ' "$RAW" | sort -u
raw ""
raw "raw log: $RAW"
