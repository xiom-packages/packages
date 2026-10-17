#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB page-file crash/reopen test -- durable page store primitive.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Mirrors scripts/page_crash_test.ps1:
#   1. writer upserts N CRC32C-sealed pages, then hangs (crash simulation);
#   2. hard-kill the writer process GROUP once N pages are durable on disk;
#   3. append a torn tail (malformed, no newline) -- crash mid-write;
#   4. reopen: verify every page (count, checksum, byte pattern; torn skipped);
#   5. upsert one more page (rewrite heals the torn tail) and verify N+1.
#
# Usage: scripts/page_crash_test.sh [--pages N] [--timeout-sec S]
# Exit:  0 = green, 1 = failed.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dev-env.sh
. "$SCRIPT_DIR/dev-env.sh"

PAGES=20
TIMEOUT_SEC=90
while [ $# -gt 0 ]; do
  case "$1" in
    --pages) PAGES=${2:?missing value}; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC=${2:?missing value}; shift 2 ;;
    -h|--help) printf 'Usage: page_crash_test.sh [--pages N] [--timeout-sec S]\n'; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'page-crash: XIOM_COMPILER not resolved; source scripts/dev-env.sh\n' >&2
  exit 2
fi

PROBE="$REPO_ROOT/tests/probes/probe_page_file.xi"
LOG_DIR="$REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
PAGE_FILE="$LOG_DIR/crash-pages.seg"
rm -f "$PAGE_FILE"

PASS=0
FAIL=0
check() {
  if [ "$2" -eq 0 ]; then printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1));
  else printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); fi
}

invoke_mode() { # mode n [last_id]
  local mode=$1 n=$2 last_id=${3:-}
  export ORBITDB_PAGE_FILE="$PAGE_FILE"
  export ORBITDB_PAGE_MODE="$mode"
  export ORBITDB_PAGE_N="$n"
  if [ -n "$last_id" ]; then export ORBITDB_PAGE_LAST_ID="$last_id"; else unset ORBITDB_PAGE_LAST_ID; fi
  "$SCRIPT_DIR/run.sh" "$PROBE" --timeout-sec 180 --quiet
  return $?
}

# --- phase 1: writer upserts PAGES records, then hangs ----------------------
export ORBITDB_PAGE_FILE="$PAGE_FILE"
export ORBITDB_PAGE_MODE="write"
export ORBITDB_PAGE_N="$PAGES"
setsid "$XIOM_COMPILER" --run "$PROBE" -o "$LOG_DIR/page-writer-$$.bin" >"$LOG_DIR/page-writer.out" 2>&1 &
WRITER_PID=$!

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
OBSERVED=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -f "$PAGE_FILE" ]; then
    OBSERVED=$(grep -c '|' "$PAGE_FILE" 2>/dev/null || true)
    [ -n "$OBSERVED" ] || OBSERVED=0
    [ "$OBSERVED" -ge "$PAGES" ] && break
  fi
  if ! kill -0 "$WRITER_PID" 2>/dev/null && [ ! -f "$PAGE_FILE" ]; then break; fi
  sleep 0.3
done
check "writer wrote $PAGES pages (observed=$OBSERVED)" "$([ "$OBSERVED" -ge "$PAGES" ] && echo 0 || echo 1)"

# --- phase 2: hard-kill the group + torn tail ------------------------------
kill -9 -"$WRITER_PID" 2>/dev/null || kill -9 "$WRITER_PID" 2>/dev/null
wait "$WRITER_PID" 2>/dev/null || true
printf '88|5|' >> "$PAGE_FILE"
printf 'crash: killed writer, page file=%s bytes, torn tail appended\n' "$(wc -c < "$PAGE_FILE")"

# --- phase 3: reopen, verify all pages despite the torn tail ---------------
invoke_mode verify "$PAGES" >/dev/null 2>&1
check "reopen verifies $PAGES pages (checksums + pattern, torn skipped)" "$?"

# --- phase 4: upsert one more page (rewrite heals the torn tail) -----------
invoke_mode write1 "$PAGES" >/dev/null 2>&1
check "upsert after torn tail heals (write1 exit 0)" "$?"

# --- phase 5: N+1 and last-page integrity -----------------------------------
invoke_mode verify "$((PAGES + 1))" "9999" >/dev/null 2>&1
check "reopen sees $((PAGES + 1)) pages incl. healed upsert" "$?"

printf 'crash: pass=%s fail=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then printf 'page-crash: GREEN\n'; exit 0; fi
printf 'page-crash: RED\n'
exit 1
