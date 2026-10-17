#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB crash/reopen test -- durable WAL critical primitive (Linux).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Mirrors scripts/crash_test.ps1:
#   1. writer appends N records, then hangs (crash simulation);
#   2. hard-kill the writer process GROUP once N records are visible;
#   3. append a torn tail ("torn|", no newline) -- crash mid-record;
#   4. reopen: replay the segment, expect exactly N records (torn skipped);
#   5. append one more record (torn-tail healing) and expect N+1.
#
# Usage: scripts/crash_test.sh [--events N] [--timeout-sec S]
# Exit:  0 = green, 1 = failed.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dev-env.sh
. "$SCRIPT_DIR/dev-env.sh"

EVENTS=20
TIMEOUT_SEC=90
while [ $# -gt 0 ]; do
  case "$1" in
    --events) EVENTS=${2:?missing value}; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC=${2:?missing value}; shift 2 ;;
    -h|--help) printf 'Usage: crash_test.sh [--events N] [--timeout-sec S]\n'; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'crash: XIOM_COMPILER not resolved; source scripts/dev-env.sh\n' >&2
  exit 2
fi

PROBE="$REPO_ROOT/tests/probes/probe_wal_file.xi"
LOG_DIR="$REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
WAL_FILE="$LOG_DIR/crash-wal.seg"
rm -f "$WAL_FILE"

PASS=0
FAIL=0
check() {
  if [ "$2" -eq 0 ]; then printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1));
  else printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); fi
}

invoke_mode() { # mode n [last_key last_val]
  local mode=$1 n=$2 last_key=${3:-} last_val=${4:-}
  export ORBITDB_WAL_FILE="$WAL_FILE"
  export ORBITDB_WAL_MODE="$mode"
  export ORBITDB_WAL_N="$n"
  if [ -n "$last_key" ]; then export ORBITDB_WAL_LAST_KEY="$last_key"; else unset ORBITDB_WAL_LAST_KEY; fi
  if [ -n "$last_val" ]; then export ORBITDB_WAL_LAST_VAL="$last_val"; else unset ORBITDB_WAL_LAST_VAL; fi
  "$SCRIPT_DIR/run.sh" "$PROBE" --timeout-sec 180 --quiet
  return $?
}

# --- phase 1: writer appends EVENTS records, then hangs --------------------
export ORBITDB_WAL_FILE="$WAL_FILE"
export ORBITDB_WAL_MODE="write"
export ORBITDB_WAL_N="$EVENTS"
# setsid puts the compiler + program in a new process group so the hard-kill
# takes down the hanging program too (kill -PGID below).
setsid "$XIOM_COMPILER" --run "$PROBE" -o "$LOG_DIR/crash-writer-$$.bin" >"$LOG_DIR/crash-writer.out" 2>&1 &
WRITER_PID=$!

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
OBSERVED=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -f "$WAL_FILE" ]; then
    OBSERVED=$(grep -c '|' "$WAL_FILE" 2>/dev/null || true)
    [ -n "$OBSERVED" ] || OBSERVED=0
    [ "$OBSERVED" -ge "$EVENTS" ] && break
  fi
  if ! kill -0 "$WRITER_PID" 2>/dev/null && [ ! -f "$WAL_FILE" ]; then break; fi
  sleep 0.3
done
check "writer wrote $EVENTS records (observed=$OBSERVED)" "$([ "$OBSERVED" -ge "$EVENTS" ] && echo 0 || echo 1)"

# --- phase 2: hard-kill the group + torn tail ------------------------------
kill -9 -"$WRITER_PID" 2>/dev/null || kill -9 "$WRITER_PID" 2>/dev/null
wait "$WRITER_PID" 2>/dev/null || true
printf 'torn|' >> "$WAL_FILE"
printf 'crash: killed writer, segment=%s bytes, torn tail appended\n' "$(wc -c < "$WAL_FILE")"

# --- phase 3: reopen, prefix intact despite torn tail ----------------------
invoke_mode verify "$EVENTS" >/dev/null 2>&1
check "reopen replays prefix ($EVENTS) with torn tail skipped" "$?"

# --- phase 4: heal + append one more record --------------------------------
invoke_mode append1 "$EVENTS" >/dev/null 2>&1
check "append after torn tail heals (append1 exit 0)" "$?"

# --- phase 5: N+1 and last-record integrity --------------------------------
invoke_mode verify "$((EVENTS + 1))" "9999" "99990" >/dev/null 2>&1
check "reopen sees $((EVENTS + 1)) records incl. healed append" "$?"

printf 'crash: pass=%s fail=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then printf 'crash: GREEN\n'; exit 0; fi
printf 'crash: RED\n'
exit 1
