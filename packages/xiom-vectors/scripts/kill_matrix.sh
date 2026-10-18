#!/usr/bin/env bash
# XIOM XVECTOR -- D5 kill matrix (WSL/Linux).
# Spawns out/kill_writer, kills it mid-stream (SIGKILL), then verifies every
# acknowledged record survives recovery via out/kill_check.
# Usage: bash scripts/kill_matrix.sh [iters=6]
set -u
cd "$(dirname "$0")/.." || exit 1

# shellcheck disable=SC1091
. scripts/dev-env.sh >/dev/null 2>&1

bash scripts/build.sh tests/harness/kill_writer.xi kill_writer >/dev/null 2>&1 || { echo "kill-matrix: kill_writer build FAILED"; exit 1; }
bash scripts/build.sh tests/harness/kill_check.xi kill_check >/dev/null 2>&1 || { echo "kill-matrix: kill_check build FAILED"; exit 1; }

iters="${1:-6}"
fails=0

for i in $(seq 1 "$iters"); do
  home="out/kill_$i"
  rm -f "$home.seg" "$home.ack" "$home.ckpt"

  ./out/kill_writer "$home.seg" "$home.ack" 1000000 &
  pid=$!

  # Wait until >= 5 ids are acknowledged (up to 5 s), then a beat more so the
  # process is inside the write/fsync stream, then SIGKILL.
  acked=0
  for _ in $(seq 1 200); do
    [ -f "$home.ack" ] && acked=$(wc -l < "$home.ack")
    [ "$acked" -ge 5 ] && break
    sleep 0.025
  done
  sleep 0.06
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  ./out/kill_check "$home.seg" "$home.ckpt" "$home.ack"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "kill-matrix iter $i: PASS (acked=$acked)"
  else
    echo "kill-matrix iter $i: FAIL (rc=$rc acked=$acked)"
    fails=$((fails + 1))
  fi
done

if [ "$fails" -eq 0 ]; then
  echo "kill-matrix: ALL $iters ITERATIONS PASS"
  exit 0
fi
echo "kill-matrix: $fails/$iters ITERATIONS FAILED"
exit "$fails"
