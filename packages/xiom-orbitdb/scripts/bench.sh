#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB benchmark runner (Linux/WSL) -- baseline numbers per release.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Mirrors scripts/bench.ps1: runs tests/probes/probe_bench.xi and tees the
# result to probe-logs/bench-<timestamp>.txt. Numbers are recorded in
# docs/PRODUCTION-READINESS.md (G1) -- regression baselines, not claims.
#
# Usage: scripts/bench.sh [--n 10000] [--order 4]
# Exit:  0 = all cases ran.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dev-env.sh
. "$SCRIPT_DIR/dev-env.sh"

N=10000
ORDER=4
while [ $# -gt 0 ]; do
  case "$1" in
    --n) N=${2:?missing value}; shift 2 ;;
    --order) ORDER=${2:?missing value}; shift 2 ;;
    -h|--help) printf 'Usage: bench.sh [--n 10000] [--order 4]\n'; exit 0 ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'bench: XIOM_COMPILER not resolved; source scripts/dev-env.sh\n' >&2
  exit 2
fi

PROBE="$REPO_ROOT/tests/probes/probe_bench.xi"
LOG_DIR="$REPO_ROOT/probe-logs"
mkdir -p "$LOG_DIR"
OUT="$LOG_DIR/bench-$(date +%Y%m%d-%H%M%S).txt"

export ORBITDB_BENCH_N="$N"
export ORBITDB_BENCH_ORDER="$ORDER"
export ORBITDB_BENCH_CASE="all"
# Keep the scratch segment OFF the Windows mount: per-append open/close over
# DrvFs (9p) is ~20x slower than a native filesystem and skews the numbers.
export ORBITDB_BENCH_WAL="${TMPDIR:-/tmp}/orbitdb-bench.wal"

printf 'bench: n=%s order=%s -> %s\n' "$N" "$ORDER" "$OUT"
"$SCRIPT_DIR/run.sh" "$PROBE" --timeout-sec 900 | tee "$OUT"
exit "${PIPESTATUS[0]}"
