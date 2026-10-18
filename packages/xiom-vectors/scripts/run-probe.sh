#!/usr/bin/env bash
# ============================================================================
# XIOM XVECTOR probe runner (Linux/WSL) -- build one probe and run it N times
# (default 2) under a `timeout` watchdog; gate on exit code.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage: scripts/run-probe.sh tests/probes/probe_hello.xi [runs] [timeout_sec]
# Exit code: 0 = all runs green; nonzero = first failing run's exit code.
# ============================================================================
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

src="${1:-}"
if [ -z "$src" ]; then
  echo "usage: scripts/run-probe.sh <probe.xi> [runs] [timeout_sec]" >&2
  exit 2
fi
[ -f "$src" ] || src="$repo_root/$src"
if [ ! -f "$src" ]; then
  echo "run-probe: source not found: $src" >&2
  exit 2
fi
runs="${2:-2}"
timeout_sec="${3:-60}"
name="$(basename "$src" .xi)"
exe="$repo_root/out/$name"

"$script_dir/build.sh" "$src" "$name" || exit $?

failed_run=0
i=1
while [ "$i" -le "$runs" ]; do
  out_file="$repo_root/out/${name}_run$i.out"
  err_file="$repo_root/out/${name}_run$i.err"
  ( cd "$repo_root" && timeout "$timeout_sec" "$exe" ) >"$out_file" 2>"$err_file"
  code=$?
  if [ "$code" -eq 124 ]; then
    echo "run-probe: run $i: TIMEOUT after ${timeout_sec}s"
    [ "$failed_run" -eq 0 ] && failed_run=124
  elif [ "$code" -ne 0 ]; then
    echo "run-probe: run $i: FAILED (exit $code)"
    sed 's/^/  /' "$out_file"
    [ "$failed_run" -eq 0 ] && failed_run=$code
  else
    echo "run-probe: run $i: GREEN (exit 0)"
    sed 's/^/  /' "$out_file"
  fi
  i=$((i + 1))
done

if [ "$failed_run" -ne 0 ]; then
  echo "run-probe: FAILED"
  exit "$failed_run"
fi
echo "run-probe: ALL $runs RUNS GREEN ($name)"
exit 0
