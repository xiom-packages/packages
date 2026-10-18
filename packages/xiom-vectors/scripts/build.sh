#!/usr/bin/env bash
# ============================================================================
# XIOM XVECTOR builder (Linux/WSL) -- compile one XIOM file to out/<name>
# under the pinned toolchain, with a hard compile watchdog (`timeout`).
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   scripts/build.sh tests/probes/probe_vector_store.xi
#   scripts/build.sh tests/test_conformance.xi conf
# Exit code: compiler exit code (0 = built); 124 = watchdog timeout.
# ============================================================================
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER:-}" ]; then
  # shellcheck source=dev-env.sh
  . "$script_dir/dev-env.sh"
fi
if [ -z "${XIOM_COMPILER:-}" ]; then
  echo "build: XIOM_COMPILER not resolved; check scripts/dev-env.sh" >&2
  exit 1
fi

src="${1:-}"
if [ -z "$src" ]; then
  echo "usage: scripts/build.sh <file.xi> [name] [timeout_sec]" >&2
  exit 2
fi
if [ ! -f "$src" ]; then
  echo "build: source not found: $src" >&2
  exit 2
fi

name="${2:-$(basename "$src" .xi)}"
timeout_sec="${3:-240}"
out_dir="$repo_root/out"
mkdir -p "$out_dir"
out_exe="$out_dir/$name"

# Never let a stale binary masquerade as a fresh build.
rm -f "$out_exe"

echo "build: $src -> $out_exe"
log_out="$(mktemp)"
log_err="$(mktemp)"
# XVECTOR_SEQUENTIAL=1 is an A/B DIAGNOSTIC switch for XVC-C-05 (per-build
# nondeterministic lowering of Float32 arithmetic to integer bit-pattern
# ops). It is NOT a reliable workaround: correctness flips per build with
# the flag in both directions. Every evidence build must run its own numeric
# assertions; treat a red check as a build rejection and rebuild.
seq_flag=""
if [ "${XVECTOR_SEQUENTIAL:-}" = "1" ]; then
  seq_flag="--sequential"
  echo "build: --sequential (XVC-C-05 A/B diagnostic)"
fi
( cd "$repo_root" && timeout "$timeout_sec" "$XIOM_COMPILER" $seq_flag -o "$out_exe" "$src" ) >"$log_out" 2>"$log_err"
code=$?
cat "$log_out" "$log_err" | sed '/^\s*$/d'
rm -f "$log_out" "$log_err"

if [ "$code" -eq 124 ]; then
  echo "build: TIMEOUT after ${timeout_sec}s -- process tree killed"
  exit 124
fi
if [ "$code" -ne 0 ]; then
  echo "build: FAILED (compiler exit $code)"
  exit "$code"
fi
if [ ! -f "$out_exe" ]; then
  echo "build: compiler exit 0 but $out_exe missing"
  exit 1
fi

echo "build: OK $out_exe"
exit 0
