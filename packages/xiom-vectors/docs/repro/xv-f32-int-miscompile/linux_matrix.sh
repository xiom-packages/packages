#!/usr/bin/env bash
# XVECTOR repro helper (WSL/Linux): compile the XVC-C-05 probes N times and
# print the observed dot bits + exit code per build.
# Usage: bash docs/repro/xv-f32-int-miscompile/linux_matrix.sh [N]
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../../.." || exit 2
n="${1:-3}"

echo "== probe_failing.xi (bundle copy) x$n"
i=1
while [ "$i" -le "$n" ]; do
  bash scripts/build.sh docs/repro/xv-f32-int-miscompile/probe_failing.xi "pf_m$i" 240 >/dev/null 2>&1
  line=$(out/pf_m"$i" 2>&1 | grep "diag p2 dot" | head -n 1)
  out/pf_m"$i" >/dev/null 2>&1
  echo "  build$i: exit=$? | $line"
  i=$((i + 1))
done

echo "== tests/probes/probe_vector_store.xi x$n"
i=1
while [ "$i" -le "$n" ]; do
  bash scripts/build.sh tests/probes/probe_vector_store.xi "pvs_m$i" 240 >/dev/null 2>&1
  line=$(out/pvs_m"$i" 2>&1 | grep "diag p2 dot" | head -n 1)
  out/pvs_m"$i" >/dev/null 2>&1
  echo "  build$i: exit=$? | $line"
  i=$((i + 1))
done

echo "== probe_failing.xi --sequential x$n"
i=1
while [ "$i" -le "$n" ]; do
  XVECTOR_SEQUENTIAL=1 bash scripts/build.sh docs/repro/xv-f32-int-miscompile/probe_failing.xi "pf_s$i" 240 >/dev/null 2>&1
  line=$(out/pf_s"$i" 2>&1 | grep "diag p2 dot" | head -n 1)
  out/pf_s"$i" >/dev/null 2>&1
  echo "  build$i: exit=$? | $line"
  i=$((i + 1))
done
