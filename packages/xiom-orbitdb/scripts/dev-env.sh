#!/usr/bin/env bash
# ============================================================================
# XIOM ORBITDB dev environment (Linux/WSL) -- dot-source in every terminal:
#   . scripts/dev-env.sh
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# VERSION POLICY (owner decision, inherited from PULSE): ORBITDB tracks the
# LATEST compiler / stdlib / packages to harden the ecosystem by real-world
# use. Record exact versions and lane hashes in SESSION.md at every wrap.
#
# As of 2026-10-17 (compiler v0.64.6 adoption): compiler v0.64.6 (mirrors
# scripts/dev-env.ps1, which pins the Windows extract
# %LOCALAPPDATA%\xiom.new-20261016-233955; WSL canonical ~/.local/bin/xiom
# reports v0.64.6 on install root ~/.local/share/xiom,
# sha256 855bd7cc82c0f24f... == xiom-0.64.6-linux-x64.tar.gz bin/xiom):
#   compiler  xiom (Linux install, canonical layout ~/.local/share/xiom)
#   stdlib    $XIOM_STDLIB if set; else the WSL-mounted lane checkout
#             /mnt/e/xiom-lang/stdlib when present; else the compiler's
#             bundled lib/xiom tree (release-artifact behavior)
#   OWNER DIRECTIVE 2026-10-17: ALWAYS use the latest RELEASED stdlib (that
#   is where requested fixes land). The bundled release tree is the DEFAULT;
#   the stdlib lane checkout is early-warning/WIP and opt-in only -- export
#   XIOM_STDLIB=/mnt/e/xiom-lang/stdlib before sourcing to use it (never
#   edit that tree).
#   packages  <xiom_home>/packages (xiom pkg install; WSL layout ~/xiom)
#
# XIOM_RUNTIME_DIR: the 2026-10-13 lane-runtime override (M1.2 S4) is
# DROPPED as of 2026-10-15 -- the v0.64.6 archive re-vendors stdlib/runtime
# carrying wave 139 (>> the 115/117/118 primitives the S4 slice adopted).
# Any inherited override is actively unset; the stock pin is authoritative.
#
# Safe to source repeatedly; never exits the caller on warnings.
# ============================================================================

# --- compiler resolution ----------------------------------------------------
if [ -z "${XIOM_COMPILER:-}" ]; then
  if command -v xiom >/dev/null 2>&1; then
    XIOM_COMPILER="$(command -v xiom)"
  elif [ -x "$HOME/.local/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.local/bin/xiom"
  elif [ -x "$HOME/.local/share/xiom/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.local/share/xiom/bin/xiom"
  fi
fi
[ -n "${XIOM_COMPILER:-}" ] && export XIOM_COMPILER

# --- stock runtime (v0.64.6 re-vendor carries wave 139) ---------------------
# The 2026-10-13 lane-runtime override is retired; never inherit a stale one.
unset XIOM_RUNTIME_DIR

# --- stdlib -----------------------------------------------------------------
# RELEASE default: leave XIOM_STDLIB unset -> the compiler's bundled
# release tree. An explicitly exported XIOM_STDLIB is an opt-in
# early-warning run against the stdlib lane checkout -- keep it as-is.
[ -n "${XIOM_STDLIB:-}" ] && export XIOM_STDLIB

# --- report -----------------------------------------------------------------
if [ -z "${XIOM_COMPILER:-}" ] || [ ! -x "${XIOM_COMPILER}" ]; then
  printf 'dev-env: WARNING XIOM_COMPILER not found (install the Linux toolchain or export XIOM_COMPILER)\n' >&2
  if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0; else exit 0; fi
fi

_ver="$("$XIOM_COMPILER" --version 2>&1 | head -n 1)"
printf 'dev-env: %s\n' "$_ver"
printf 'dev-env: XIOM_COMPILER = %s\n' "$XIOM_COMPILER"
printf 'dev-env: XIOM_STDLIB   = %s\n' "${XIOM_STDLIB:-<unset: compiler bundled stdlib>}"
printf 'dev-env: XIOM_RUNTIME_DIR = <unset> (stock v0.64.6 runtime; override retired 2026-10-15)\n'
unset _ver
