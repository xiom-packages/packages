#!/usr/bin/env bash
# ============================================================================
# Deterministic fuzz/property harness runner (H3) -- mirrors scripts/fuzz.ps1.
# Usage: scripts/fuzz.sh [--timeout-sec S]
# Exit:  the probe's exit code (0 = green); 124 on watchdog timeout.
# ============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$REPO_ROOT/probe-logs"

if [ $# -eq 0 ]; then
  set -- --timeout-sec 600
fi

exec "$SCRIPT_DIR/run.sh" "$REPO_ROOT/tests/probes/probe_fuzz.xi" "$@"
