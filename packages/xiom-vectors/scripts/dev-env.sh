#!/usr/bin/env bash
# ============================================================================
# XIOM XVECTOR dev environment (Linux/WSL) -- dot-source in every terminal:
#   . scripts/dev-env.sh
# ============================================================================
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# VERSION POLICY: XVECTOR tracks the LATEST compiler / stdlib / packages
# (owner decision, inherited from PULSE). Record exact versions + lane hashes
# in SESSION.md at every wrap.
#
# ISOLATION (2026-10-10): concurrent sessions on the build machine had the
# shared toolchain state deleted mid-battery (both package homes and parts of
# the Windows install root); see the bus incident REL-20261010-1835-xvector.
# The lane therefore pins its OWN toolchain and package home:
#   compiler  ~/.xvector-toolchain/bin/xiom when present (lane-local copy of
#             the pinned v0.64.3); else `xiom` from PATH / the shared install
#   packages  ~/.xvector-home (lane-local XIOM_HOME; xiom pkg installs of
#             xiom.wal 0.1.0 + xiom.metrics 0.2.0 + xiom.rate 0.2.0)
#   stdlib    $XIOM_STDLIB if set; else the WSL-mounted lane checkout
#             /mnt/e/xiom-lang/stdlib when present; else the compiler's
#             bundled lib/xiom tree (release-artifact behavior)
#
# XIOM_RUNTIME_DIR is retired since v0.64.0 (verified env-free). Always cleared.
# Safe to source repeatedly; never exits the caller on warnings.
# ============================================================================

# --- isolation: lane-local package home -------------------------------------
if [ -z "${XIOM_HOME:-}" ]; then
  XIOM_HOME="$HOME/.xvector-home"
fi
mkdir -p "$XIOM_HOME" 2>/dev/null
export XIOM_HOME

# --- compiler resolution ----------------------------------------------------
if [ -z "${XIOM_COMPILER:-}" ]; then
  if [ -x "$HOME/.xvector-toolchain/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.xvector-toolchain/bin/xiom"
  elif command -v xiom >/dev/null 2>&1; then
    XIOM_COMPILER="$(command -v xiom)"
  elif [ -x "$HOME/.local/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.local/bin/xiom"
  elif [ -x "$HOME/.local/share/xiom/bin/xiom" ]; then
    XIOM_COMPILER="$HOME/.local/share/xiom/bin/xiom"
  fi
fi
[ -n "${XIOM_COMPILER:-}" ] && export XIOM_COMPILER

# --- retired runtime override ----------------------------------------------
unset XIOM_RUNTIME_DIR

# --- stdlib -----------------------------------------------------------------
if [ -z "${XIOM_STDLIB:-}" ] && [ -d /mnt/e/xiom-lang/stdlib ]; then
  # WSL on the development machine: use the same lane checkout as Windows.
  XIOM_STDLIB=/mnt/e/xiom-lang/stdlib
fi
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
printf 'dev-env: XIOM_HOME     = %s (lane-local)\n' "$XIOM_HOME"
printf 'dev-env: XIOM_RUNTIME_DIR retired (v0.64.1 R65 install-layout fix)\n'
unset _ver
