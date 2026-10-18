#!/usr/bin/env bash
# SBOM + security gate (M-S4) -- .sh twin of scripts/sbom.ps1.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/out"
mkdir -p "$out"

stdlib_pin="$(git -C /mnt/e/xiom-lang/stdlib rev-parse --short HEAD 2>/dev/null || echo unknown)"
# `|| true` absorbs the pipefail/SIGPIPE race when head closes early; without
# it the fallback echo would append "unknown" to the captured version line.
compiler="$(xiom --version 2>/dev/null | head -n 1 || true)"
if [ -z "$compiler" ]; then compiler="unknown"; fi
app_version="$(head -1 "$root/VERSION" 2>/dev/null || echo unknown)"

if grep -RIn --include='*.xi' 'unsafe' "$root/src" >/dev/null 2>&1; then
  echo "sbom: FAILED -- unsafe usage found in src/:"
  grep -RIn --include='*.xi' 'unsafe' "$root/src" || true
  exit 1
fi

{
  printf '{\n'
  printf '  "project": "xiom.xvector",\n'
  printf '  "version": "%s",\n' "$app_version"
  printf '  "compiler": "%s",\n' "$compiler"
  printf '  "stdlib_pin": "%s",\n' "$stdlib_pin"
  printf '  "registry_dependencies": [],\n'
  printf '  "unsafe_blocks_in_src": 0,\n'
  printf '  "modules": [\n'
  first=1
  while IFS= read -r f; do
    rel="${f#"$root"/}"
    hash="$(sha256sum "$f" | cut -d' ' -f1)"
    if [ "$first" -eq 0 ]; then printf ',\n'; fi
    first=0
    printf '    { "path": "%s", "sha256": "%s" }' "$rel" "$hash"
  done < <(find "$root/src" -name '*.xi' -type f | sort)
  printf '\n  ]\n}\n'
} > "$out/sbom.json"
count="$(find "$root/src" -name '*.xi' -type f | wc -l | tr -d ' ')"
echo "sbom: OK -- $count modules, unsafe=0, compiler $compiler"
