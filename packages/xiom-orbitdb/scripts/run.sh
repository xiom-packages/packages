#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB runner -- compile+run one XIOM file under the tracked
# toolchain, with a hard watchdog and fail-closed exit-code handling.
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Usage:
#   scripts/run.sh tests/test_conformance.xi
#   scripts/run.sh tests/probes/probe_hello.xi --timeout-sec 300
#
# Exit code: the program's reported exit code (1 on compile failure,
# 124 on watchdog timeout). Never treats a timeout or an empty run as green.
# ============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dev-env.sh
. "$SCRIPT_DIR/dev-env.sh"

usage() {
  cat <<'EOF'
Usage: run.sh <file.xi> [--timeout-sec N] [--quiet]

  --timeout-sec N    watchdog seconds (default 120)
  --quiet            do not echo program output
EOF
}

FILE=""
TIMEOUT_SEC=120
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --timeout-sec) TIMEOUT_SEC=${2:?missing value}; shift 2 ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) FILE=$1; shift ;;
  esac
done
[ -n "$FILE" ] || { usage >&2; exit 2; }
[ -f "$FILE" ] || { printf 'run: file not found: %s\n' "$FILE" >&2; exit 2; }

if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'run: XIOM_COMPILER not resolved; source scripts/dev-env.sh\n' >&2
  exit 2
fi

FILE_ABS=$(realpath "$FILE")
OUT=$(mktemp "${TMPDIR:-/tmp}/orbitdb-run-XXXXXX")
# Unique output binary per invocation (S4 harness hardening): sharing a.out in
# the repo root collides on DrvFs when a just-killed writer's image lingers
# ("Text file busy", os error 26) and cross-run overwrites race.
BIN=$(mktemp "${TMPDIR:-/tmp}/orbitdb-bin-XXXXXX")
rm -f "$BIN"
( cd "$REPO_ROOT" && exec timeout "$TIMEOUT_SEC" "$XIOM_COMPILER" --run "$FILE_ABS" -o "$BIN" ) >"$OUT" 2>&1
RC=$?

if [ "$RC" -eq 124 ]; then
  sed -n '1,200p' "$OUT"
  rm -f "$OUT" "$BIN"
  printf 'run: TIMEOUT after %ss\n' "$TIMEOUT_SEC"
  exit 124
fi

[ "$QUIET" -eq 0 ] && sed -n '1,200p' "$OUT"

# `xiom --run` prints the program's exit code on its own "exit code:" line and
# can exit 0 even when the program crashed; trust the reported code.
PROGRAM_EXIT=""
LINE=$(grep -oE 'exit code:[[:space:]]*-?[0-9]+' "$OUT" | tail -n 1 || true)
if [ -n "$LINE" ]; then
  PROGRAM_EXIT=$(printf '%s' "$LINE" | grep -oE -- '-?[0-9]+$')
fi
rm -f "$OUT" "$BIN"

if [ -n "$PROGRAM_EXIT" ]; then
  printf 'run: program_exit=%s compiler_exit=%s\n' "$PROGRAM_EXIT" "$RC"
  exit "$PROGRAM_EXIT"
fi
printf 'run: compiler_exit=%s (no exit code: line)\n' "$RC"
exit "$RC"
