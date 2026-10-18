#!/usr/bin/env bash
# ============================================================================
# XIOM XVECTOR benchmark runner (M-G2) -- build bench/bench_main.xi and run
# it. Usage: bash scripts/bench.sh [quick|medium|full] (default medium).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Exit code: 0 = green (report written); nonzero = failure.
# ============================================================================
set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
mode="${1:-medium}"
export XV_BENCH_MODE="$mode"

if ! bash scripts/build.sh bench/bench_main.xi bench_main; then
  echo "bench: build failed"
  exit 1
fi
if ! ./out/bench_main; then
  echo "bench: FAILED"
  exit 1
fi
echo "bench: GREEN ($mode); report out/bench_report.json"
exit 0
