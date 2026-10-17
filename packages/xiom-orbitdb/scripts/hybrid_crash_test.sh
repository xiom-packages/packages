#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB <-> XVECTOR hybrid crash/recovery test (hard kill both stores).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Mirrors scripts/hybrid_crash_test.ps1:
#   1. writer: ingest N rows (transactions, mid checkpoint) + N-SKIP
#      embeddings, bump LAG row versions without re-embedding, persist the
#      vector WAL, then hang.
#   2. the harness hard-kills the process group and appends a torn tail to
#      the row WAL (the vector WAL stays a complete checkpoint).
#   3. verify: reopen both stores (row snapshot + WAL replay, vector WAL
#      load + recover), run the consumer repair pass, and require 100% join
#      integrity; a second verify must find nothing to repair (idempotent).
#
# Usage: scripts/hybrid_crash_test.sh [--keys N] [--timeout-sec S]
# Exit:  0 = green, 1 = failed.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dev-env.sh
. "$SCRIPT_DIR/dev-env.sh"

KEYS=1000
TIMEOUT_SEC=180
while [ $# -gt 0 ]; do
  case "$1" in
    --keys) KEYS=${2:?missing value}; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC=${2:?missing value}; shift 2 ;;
    -h|--help) printf 'Usage: hybrid_crash_test.sh [--keys N] [--timeout-sec S]\n'; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'hybrid-crash: XIOM_COMPILER not resolved; source scripts/dev-env.sh\n' >&2
  exit 2
fi

PROBE="$REPO_ROOT/tests/hybrid/probe_hybrid.xi"
LOG_DIR="$REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
ROWS_FILE="$LOG_DIR/hybrid-crash.db"
VEC_FILE="$LOG_DIR/hybrid-crash.wal"
rm -f "$ROWS_FILE" "$ROWS_FILE.snap" "$VEC_FILE" "$VEC_FILE.tmp"

export ORBITDB_HYBRID_ROWS="$ROWS_FILE"
export ORBITDB_HYBRID_VEC="$VEC_FILE"
export ORBITDB_HYBRID_N="$KEYS"
export ORBITDB_HYBRID_DIM=8
export ORBITDB_HYBRID_SKIP=10
export ORBITDB_HYBRID_LAG=3
export ORBITDB_HYBRID_CHUNK=200

PASS=0
FAIL=0
check() {
  if [ "$2" -eq 0 ]; then printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1));
  else printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); fi
}

# --- phase 1: writer ingests + persists + hangs -----------------------------
export ORBITDB_HYBRID_MODE=writer
setsid "$XIOM_COMPILER" --run "$PROBE" -o "$LOG_DIR/hybrid-writer-$$.bin" >"$LOG_DIR/hybrid-writer.out" 2>&1 &
WRITER_PID=$!

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
OBSERVED=-1
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -f "$VEC_FILE" ]; then
    OBSERVED=$(wc -c < "$VEC_FILE" | tr -d ' ')
    [ "$OBSERVED" -gt 0 ] && break
  fi
  kill -0 "$WRITER_PID" 2>/dev/null || break
  sleep 0.3
done
[ -n "$OBSERVED" ] || OBSERVED=0
check "writer reached ready point (vector WAL persisted, bytes=$OBSERVED)" "$([ "$OBSERVED" -gt 0 ] && echo 0 || echo 1)"

# --- phase 2: hard-kill the group + torn row tail ---------------------------
kill -9 -"$WRITER_PID" 2>/dev/null || kill -9 "$WRITER_PID" 2>/dev/null
wait "$WRITER_PID" 2>/dev/null || true
sleep 0.3
ROW_BYTES=-1
if [ -f "$ROWS_FILE" ]; then
  printf 'torn|' >> "$ROWS_FILE"
  ROW_BYTES=$(wc -c < "$ROWS_FILE" | tr -d ' ')
fi
printf 'crash: killed writer, row segment=%s bytes, vector WAL=%s bytes, torn tail appended\n' "$ROW_BYTES" "$OBSERVED"

# --- phase 3: reopen both stores, repair, 100% join integrity ---------------
export ORBITDB_HYBRID_MODE=verify
V1_OUT=$( "$SCRIPT_DIR/run.sh" "$PROBE" --timeout-sec 300 2>&1 )
V1_RC=$?
printf '%s\n' "$V1_OUT"
V1_REPAIR=1; printf '%s\n' "$V1_OUT" | grep -q 'repaired=13' && V1_REPAIR=0
V1_ROWS=1; printf '%s\n' "$V1_OUT" | grep -q 'all N rows recovered' && V1_ROWS=0
V1_JOIN=1; printf '%s\n' "$V1_OUT" | grep -q '100% join integrity after repair' && V1_JOIN=0
check "verify #1 green: repair applied, 100% join integrity" "$([ "$V1_RC" -eq 0 ] && [ "$V1_REPAIR" -eq 0 ] && echo 0 || echo 1)"
check "verify #1: row store survived hard kill + torn tail" "$V1_ROWS"
check "verify #1: join gate explicitly passed" "$V1_JOIN"

# --- phase 4: idempotent second verify (nothing left to repair) -------------
V2_OUT=$( "$SCRIPT_DIR/run.sh" "$PROBE" --timeout-sec 300 2>&1 )
V2_RC=$?
V2_IDEM=1; printf '%s\n' "$V2_OUT" | grep -q 'repaired=0' && V2_IDEM=0
check "verify #2 green: idempotent (repaired=0)" "$([ "$V2_RC" -eq 0 ] && [ "$V2_IDEM" -eq 0 ] && echo 0 || echo 1)"

printf 'hybrid-crash: pass=%s fail=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then printf 'hybrid-crash: GREEN\n'; exit 0; fi
printf 'hybrid-crash: RED\n'
exit 1
