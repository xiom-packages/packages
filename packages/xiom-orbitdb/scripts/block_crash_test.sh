#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB -- byte-page block store crash harness (M1.2 S2).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Mirrors scripts/block_crash_test.ps1: per state (pages2, full2, midheader,
# compacted) the writer reaches a deterministic quiescent state, writes a
# `.ready` marker and hangs; the harness hard-kills it, appends one torn tail
# block (4096 garbage bytes), reopens, checks the committed view and performs
# a recovery append + commit.
#
# Usage: scripts/block_crash_test.sh [--pages N] [--batch B] [--timeout-sec S]
# Exit:  0 = green, 1 = failed.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dev-env.sh
. "$SCRIPT_DIR/dev-env.sh"

PAGES=60
BATCH=10
TIMEOUT_SEC=180
while [ $# -gt 0 ]; do
  case "$1" in
    --pages) PAGES=${2:?missing value}; shift 2 ;;
    --batch) BATCH=${2:?missing value}; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC=${2:?missing value}; shift 2 ;;
    -h|--help) printf 'Usage: block_crash_test.sh [--pages N] [--batch B] [--timeout-sec S]\n'; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'block-crash: XIOM_COMPILER not resolved; source scripts/dev-env.sh\n' >&2
  exit 2
fi

PROBE="$REPO_ROOT/tests/probes/probe_block_store.xi"
LOG_DIR="$REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
DB="$LOG_DIR/block-crash.db"

export ORBITDB_BLOCK_DB="$DB"
export ORBITDB_BLOCK_N="$PAGES"
export ORBITDB_BLOCK_BATCH="$BATCH"

PASS=0
FAIL=0
check() {
  if [ "$2" -eq 0 ]; then printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1));
  else printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); fi
}

for KILL_AT in pages2 full2 midheader compacted; do
  rm -f "$DB" "$DB.tmp" "$DB.ready"
  export ORBITDB_BLOCK_KILL_AT="$KILL_AT"
  export ORBITDB_BLOCK_MODE=writer
  setsid "$XIOM_COMPILER" --run "$PROBE" -o "$LOG_DIR/block-writer-$KILL_AT-$$.bin" >"$LOG_DIR/block-writer-$KILL_AT.out" 2>&1 &
  WRITER_PID=$!
  DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
  REACHED=1
  while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    if [ -f "$DB.ready" ]; then REACHED=0; break; fi
    kill -0 "$WRITER_PID" 2>/dev/null || break
    sleep 0.25
  done
  check "[$KILL_AT] writer reached the target state" "$REACHED"

  kill -9 -"$WRITER_PID" 2>/dev/null || kill -9 "$WRITER_PID" 2>/dev/null
  wait "$WRITER_PID" 2>/dev/null || true
  sleep 0.3

  # Torn tail: one garbage block in the page area.
  head -c 4096 /dev/zero | tr '\0' 'Z' >> "$DB"

  export ORBITDB_BLOCK_MODE=verify
  V_OUT=$( "$SCRIPT_DIR/run.sh" "$PROBE" --timeout-sec 300 2>&1 )
  V_RC=$?
  V_GREEN=1; printf '%s\n' "$V_OUT" | grep -q 'verify: GREEN' && V_GREEN=0
  check "[$KILL_AT] verify green (committed view + recovery append)" "$([ "$V_RC" -eq 0 ] && [ "$V_GREEN" -eq 0 ] && echo 0 || echo 1)"
done

printf 'block-crash: pass=%s fail=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then printf 'block-crash: GREEN\n'; exit 0; fi
printf 'block-crash: RED\n'
exit 1
