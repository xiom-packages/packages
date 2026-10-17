#!/usr/bin/env bash
# ============================================================================
# ORBITDB app build (Linux/WSL twin of scripts/build.ps1): compile one .xi
# source into an application binary. The --icon resource is Windows/PE-only
# (llvm-rc), so this twin builds without it.
#
# Usage: scripts/build.sh <source.xi> [out]
# Exit:  the compiler's exit code (0 = built).
# ============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dev-env.sh
. "$SCRIPT_DIR/dev-env.sh"

FILE="${1:?usage: build.sh <source.xi> [out]}"
if [[ "$FILE" != /* ]]; then
  FILE="$REPO_ROOT/$FILE"
fi
OUT="${2:-$REPO_ROOT/out/orbitdb-app}"
mkdir -p "$(dirname "$OUT")"

exec "$XIOM_COMPILER" --timeout 300 -o "$OUT" "$FILE"
