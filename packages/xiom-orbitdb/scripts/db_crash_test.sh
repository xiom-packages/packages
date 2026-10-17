#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB file-backed DB crash/recovery test (WAL-before-ack).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Mirrors scripts/db_crash_test.ps1 (five crash scenarios per run):
#   A. WAL-only: writer puts N keys, hard-kill the process GROUP, torn tail,
#      reopen recovers N, heal + put one more -> N+1.
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
# Usage: scripts/db_crash_test.sh [--keys N] [--tail T] [--tx T] [--timeout-sec S]
# Exit:  0 = green, 1 = failed.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dev-env.sh
. "$SCRIPT_DIR/dev-env.sh"

KEYS=20
TAIL=3
TX=5
TIMEOUT_SEC=90
while [ $# -gt 0 ]; do
  case "$1" in
    --keys) KEYS=${2:?missing value}; shift 2 ;;
    --tail) TAIL=${2:?missing value}; shift 2 ;;
    --tx) TX=${2:?missing value}; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC=${2:?missing value}; shift 2 ;;
    -h|--help) printf 'Usage: db_crash_test.sh [--keys N] [--tail T] [--tx T] [--timeout-sec S]\n'; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'db-crash: XIOM_COMPILER not resolved; source scripts/dev-env.sh\n' >&2
  exit 2
fi

PROBE="$REPO_ROOT/tests/probes/probe_db_file.xi"
LOG_DIR="$REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
WAL_FILE="$LOG_DIR/crash-dbfile.wal"
rm -f "$WAL_FILE" "$WAL_FILE.snap"

PASS=0
FAIL=0
check() {
  if [ "$2" -eq 0 ]; then printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1));
  else printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); fi
}

invoke_mode() { # mode n [last_key last_val path]
  local mode=$1 n=$2 last_key=${3:-} last_val=${4:-} path=${5:-$WAL_FILE}
  export ORBITDB_DB_FILE="$path"
  export ORBITDB_DB_MODE="$mode"
  export ORBITDB_DB_N="$n"
  if [ -n "$last_key" ]; then export ORBITDB_DB_LAST_KEY="$last_key"; else unset ORBITDB_DB_LAST_KEY; fi
  if [ -n "$last_val" ]; then export ORBITDB_DB_LAST_VAL="$last_val"; else unset ORBITDB_DB_LAST_VAL; fi
  "$SCRIPT_DIR/run.sh" "$PROBE" --timeout-sec 180 --quiet
  return $?
}

# Idempotent upsert step (key 9999): retry ONCE on a nonzero exit (parity
# with scripts/db_crash_test.ps1, where a transient IO failure on the
# post-heal append can happen on a loaded host). A persistent failure still
# REDs. path default = $WAL_FILE.
invoke_put1() { # n [path]
  local n=$1 path=${2:-$WAL_FILE}
  local rc=1 attempt
  for attempt in 1 2; do
    invoke_mode put1 "$n" "" "" "$path" >/dev/null 2>&1
    rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$attempt" -eq 1 ] && printf '[WARN] put1 attempt 1 rc=%s; retrying once\n' "$rc"
  done
  return "$rc"
}

# --- phase 1: writer puts KEYS records, then hangs --------------------------
export ORBITDB_DB_FILE="$WAL_FILE"
export ORBITDB_DB_MODE="write"
export ORBITDB_DB_N="$KEYS"
setsid "$XIOM_COMPILER" --run "$PROBE" -o "$LOG_DIR/dbfile-writer-$$.bin" >"$LOG_DIR/dbfile-writer.out" 2>&1 &
WRITER_PID=$!

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
OBSERVED=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -f "$WAL_FILE" ]; then
    OBSERVED=$(grep -c '|' "$WAL_FILE" 2>/dev/null || true)
    [ -n "$OBSERVED" ] || OBSERVED=0
    [ "$OBSERVED" -ge "$KEYS" ] && break
  fi
  if ! kill -0 "$WRITER_PID" 2>/dev/null && [ ! -f "$WAL_FILE" ]; then break; fi
  sleep 0.3
done
check "writer put $KEYS keys (observed=$OBSERVED)" "$([ "$OBSERVED" -ge "$KEYS" ] && echo 0 || echo 1)"

# --- phase 2: hard-kill the group + torn tail ------------------------------
kill -9 -"$WRITER_PID" 2>/dev/null || kill -9 "$WRITER_PID" 2>/dev/null
wait "$WRITER_PID" 2>/dev/null || true
printf 'torn|' >> "$WAL_FILE"
printf 'crash: killed writer, segment=%s bytes, torn tail appended\n' "$(wc -c < "$WAL_FILE")"

# --- phase 3: reopen, replay must recover exactly KEYS keys ----------------
invoke_mode verify "$KEYS" >/dev/null 2>&1
check "reopen recovers $KEYS keys (WAL replay, torn skipped)" "$?"
invoke_mode qverify "$KEYS" >/dev/null 2>&1
check "query after WAL replay: range + filter correct" "$?"

# --- phase 4: heal + put one more key --------------------------------------
invoke_put1 "$KEYS"
check "put after torn tail heals (put1 exit 0)" "$?"

# --- phase 5: N+1 and last-key integrity ------------------------------------
invoke_mode verify "$((KEYS + 1))" "9999" "99990" >/dev/null 2>&1
check "reopen recovers $((KEYS + 1)) keys incl. healed put" "$?"

# --- scenario B: checkpoint, kill before any tail (snapshot-only recovery) --
CKPT_WAL="$LOG_DIR/crash-dbfile-ckpt.wal"
CKPT_SNAP="$CKPT_WAL.snap"
rm -f "$CKPT_WAL" "$CKPT_SNAP"
export ORBITDB_DB_FILE="$CKPT_WAL"
export ORBITDB_DB_MODE="ckpt"
export ORBITDB_DB_N="$KEYS"
export ORBITDB_DB_TAIL="0"
setsid "$XIOM_COMPILER" --run "$PROBE" -o "$LOG_DIR/dbfile-writer-ckpt-$$.bin" >"$LOG_DIR/dbfile-writer-ckpt.out" 2>&1 &
WRITER_PID=$!

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
OBSERVED=-1
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -f "$CKPT_SNAP" ] && [ -f "$CKPT_WAL" ]; then
    OBSERVED=$(grep -c '|' "$CKPT_WAL" 2>/dev/null || true)
    [ -n "$OBSERVED" ] || OBSERVED=0
    [ "$OBSERVED" -eq 1 ] && break
  fi
  kill -0 "$WRITER_PID" 2>/dev/null || break
  sleep 0.3
done
check "ckpt writer reached snapshot-only point (observed=$OBSERVED)" "$([ "$OBSERVED" -eq 1 ] && echo 0 || echo 1)"
kill -9 -"$WRITER_PID" 2>/dev/null || kill -9 "$WRITER_PID" 2>/dev/null
wait "$WRITER_PID" 2>/dev/null || true
printf 'torn|' >> "$CKPT_WAL"

invoke_mode verify "$KEYS" "" "" "$CKPT_WAL" >/dev/null 2>&1
check "ckpt reopen recovers $KEYS keys from snapshot alone (torn ignored)" "$?"
invoke_mode qverify "$KEYS" "" "" "$CKPT_WAL" >/dev/null 2>&1
check "query after snapshot-only recovery: range + filter correct" "$?"
invoke_put1 "$KEYS" "$CKPT_WAL"
check "ckpt put after snapshot recovery heals tail (put1 exit 0)" "$?"
invoke_mode verify "$((KEYS + 1))" "9999" "99990" "$CKPT_WAL" >/dev/null 2>&1
check "ckpt reopen recovers $((KEYS + 1)) keys incl. healed put" "$?"

# --- scenario C: checkpoint + tail, kill mid-tail (snapshot + tail replay) --
TAIL_WAL="$LOG_DIR/crash-dbfile-tail.wal"
TAIL_SNAP="$TAIL_WAL.snap"
rm -f "$TAIL_WAL" "$TAIL_SNAP"
export ORBITDB_DB_FILE="$TAIL_WAL"
export ORBITDB_DB_MODE="ckpt"
export ORBITDB_DB_N="$KEYS"
export ORBITDB_DB_TAIL="$TAIL"
setsid "$XIOM_COMPILER" --run "$PROBE" -o "$LOG_DIR/dbfile-writer-tail-$$.bin" >"$LOG_DIR/dbfile-writer-tail.out" 2>&1 &
WRITER_PID=$!

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
OBSERVED=-1
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -f "$TAIL_SNAP" ] && [ -f "$TAIL_WAL" ]; then
    OBSERVED=$(grep -c '|' "$TAIL_WAL" 2>/dev/null || true)
    [ -n "$OBSERVED" ] || OBSERVED=0
    [ "$OBSERVED" -eq "$((1 + TAIL))" ] && break
  fi
  kill -0 "$WRITER_PID" 2>/dev/null || break
  sleep 0.3
done
check "ckpt+tail writer wrote snapshot + $TAIL tail keys (observed=$OBSERVED)" "$([ "$OBSERVED" -eq "$((1 + TAIL))" ] && echo 0 || echo 1)"
kill -9 -"$WRITER_PID" 2>/dev/null || kill -9 "$WRITER_PID" 2>/dev/null
wait "$WRITER_PID" 2>/dev/null || true
printf 'torn|' >> "$TAIL_WAL"

invoke_mode verify "$((KEYS + TAIL))" "" "" "$TAIL_WAL" >/dev/null 2>&1
check "ckpt+tail reopen recovers $((KEYS + TAIL)) keys (snapshot + tail replay)" "$?"
invoke_mode qverify "$((KEYS + TAIL))" "" "" "$TAIL_WAL" >/dev/null 2>&1
check "query after snapshot+tail recovery: range + filter correct" "$?"
invoke_put1 "$((KEYS + TAIL))" "$TAIL_WAL"
check "ckpt+tail put after recovery heals tail (put1 exit 0)" "$?"
invoke_mode verify "$((KEYS + TAIL + 1))" "9999" "99990" "$TAIL_WAL" >/dev/null 2>&1
check "ckpt+tail reopen recovers $((KEYS + TAIL + 1)) keys incl. healed put" "$?"

# --- scenario D: uncommitted txn discarded on kill --------------------------
TXN_WAL="$LOG_DIR/crash-dbfile-txn.wal"
TXN_SNAP="$TXN_WAL.snap"
rm -f "$TXN_WAL" "$TXN_SNAP"
export ORBITDB_DB_FILE="$TXN_WAL"
export ORBITDB_DB_MODE="txn"
export ORBITDB_DB_N="$KEYS"
export ORBITDB_DB_TXN_COUNT="$TX"
export ORBITDB_DB_TXN_COMMIT="0"
setsid "$XIOM_COMPILER" --run "$PROBE" -o "$LOG_DIR/dbfile-writer-txn-$$.bin" >"$LOG_DIR/dbfile-writer-txn.out" 2>&1 &
WRITER_PID=$!

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
OBSERVED=-1
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -f "$TXN_SNAP" ] && [ -f "$TXN_WAL" ]; then
    OBSERVED=$(grep -c '|' "$TXN_WAL" 2>/dev/null || true)
    [ -n "$OBSERVED" ] || OBSERVED=0
    [ "$OBSERVED" -eq "$((TX + 2))" ] && break
  fi
  kill -0 "$WRITER_PID" 2>/dev/null || break
  sleep 0.3
done
check "txn writer reached pending-txn point (observed=$OBSERVED)" "$([ "$OBSERVED" -eq "$((TX + 2))" ] && echo 0 || echo 1)"
kill -9 -"$WRITER_PID" 2>/dev/null || kill -9 "$WRITER_PID" 2>/dev/null
wait "$WRITER_PID" 2>/dev/null || true
printf 'torn|' >> "$TXN_WAL"

invoke_mode verify "$KEYS" "" "" "$TXN_WAL" >/dev/null 2>&1
check "uncommitted txn discarded: $KEYS keys recovered (no txn keys)" "$?"
invoke_mode qverify "$KEYS" "" "" "$TXN_WAL" >/dev/null 2>&1
check "query after uncommitted-txn recovery: range + filter correct" "$?"
invoke_put1 "$KEYS" "$TXN_WAL"
check "put after uncommitted-txn recovery heals WAL (put1 exit 0)" "$?"
invoke_mode verify "$((KEYS + 1))" "9999" "99990" "$TXN_WAL" >/dev/null 2>&1
check "reopen recovers $((KEYS + 1)) keys incl. healed put" "$?"

# --- scenario E: committed txn recovered on kill ----------------------------
TXNC_WAL="$LOG_DIR/crash-dbfile-txn2.wal"
TXNC_SNAP="$TXNC_WAL.snap"
rm -f "$TXNC_WAL" "$TXNC_SNAP"
export ORBITDB_DB_FILE="$TXNC_WAL"
export ORBITDB_DB_MODE="txn"
export ORBITDB_DB_N="$KEYS"
export ORBITDB_DB_TXN_COUNT="$TX"
export ORBITDB_DB_TXN_COMMIT="1"
setsid "$XIOM_COMPILER" --run "$PROBE" -o "$LOG_DIR/dbfile-writer-txn2-$$.bin" >"$LOG_DIR/dbfile-writer-txn2.out" 2>&1 &
WRITER_PID=$!

DEADLINE=$(( $(date +%s) + TIMEOUT_SEC ))
OBSERVED=-1
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  if [ -f "$TXNC_SNAP" ] && [ -f "$TXNC_WAL" ]; then
    OBSERVED=$(grep -c '|' "$TXNC_WAL" 2>/dev/null || true)
    [ -n "$OBSERVED" ] || OBSERVED=0
    [ "$OBSERVED" -eq "$((TX + 3))" ] && break
  fi
  kill -0 "$WRITER_PID" 2>/dev/null || break
  sleep 0.3
done
check "txn writer reached committed point (observed=$OBSERVED)" "$([ "$OBSERVED" -eq "$((TX + 3))" ] && echo 0 || echo 1)"
kill -9 -"$WRITER_PID" 2>/dev/null || kill -9 "$WRITER_PID" 2>/dev/null
wait "$WRITER_PID" 2>/dev/null || true
printf 'torn|' >> "$TXNC_WAL"

invoke_mode verify "$((KEYS + TX))" "" "" "$TXNC_WAL" >/dev/null 2>&1
check "committed txn recovered: $((KEYS + TX)) keys (snapshot + txn)" "$?"
invoke_mode qverify "$((KEYS + TX))" "" "" "$TXNC_WAL" >/dev/null 2>&1
check "query after committed-txn recovery: range + filter correct" "$?"
invoke_put1 "$((KEYS + TX))" "$TXNC_WAL"
check "put after committed-txn recovery heals WAL (put1 exit 0)" "$?"
invoke_mode verify "$((KEYS + TX + 1))" "9999" "99990" "$TXNC_WAL" >/dev/null 2>&1
check "reopen recovers $((KEYS + TX + 1)) keys incl. healed put" "$?"

printf 'crash: pass=%s fail=%s\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then printf 'db-crash: GREEN\n'; exit 0; fi
printf 'db-crash: RED\n'
exit 1
