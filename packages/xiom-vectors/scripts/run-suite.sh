#!/usr/bin/env bash
# ============================================================================
# XIOM XVECTOR conformance runner (Linux/WSL) -- build the suite and run it
# twice (x2 gate), each under a `timeout` watchdog; gate on exit code.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/run-suite.sh [runs] [timeout_sec]
# Exit code: 0 = all runs green; nonzero = first failing run's exit code.
# ============================================================================
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
runs="${1:-2}"
timeout_sec="${2:-60}"
exe="$repo_root/out/test_conformance"

"$script_dir/build.sh" "$repo_root/tests/test_conformance.xi" test_conformance || exit $?

failed_run=0
i=1
while [ "$i" -le "$runs" ]; do
  out_file="$repo_root/out/suite_run$i.out"
  err_file="$repo_root/out/suite_run$i.err"
  ( cd "$repo_root" && timeout "$timeout_sec" "$exe" ) >"$out_file" 2>"$err_file"
  code=$?
  err_lines=$(wc -l < "$err_file" | tr -d ' ')
  if [ "$code" -eq 124 ]; then
    echo "run-suite: run $i: TIMEOUT after ${timeout_sec}s"
    [ "$failed_run" -eq 0 ] && failed_run=124
  elif [ "$code" -ne 0 ]; then
    echo "run-suite: run $i: FAILED (exit $code)"
    tail -n 2 "$out_file" | sed 's/^/  /'
    [ "$failed_run" -eq 0 ] && failed_run=$code
  else
    echo "run-suite: run $i: GREEN (exit 0, stderr lines=$err_lines)"
    tail -n 2 "$out_file" | sed 's/^/  /'
  fi
  i=$((i + 1))
done

if [ "$failed_run" -ne 0 ]; then
  echo "run-suite: FAILED"
  exit "$failed_run"
fi
echo "run-suite: ALL $runs RUNS GREEN"
exit 0
