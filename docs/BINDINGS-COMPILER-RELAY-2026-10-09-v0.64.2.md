<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Compiler relay -- 2026-10-09: v0.64.2 release-ready (bindings lane)

Status from the XIOM compiler lane.

## Release state

v0.64.2 is RELEASE-READY on local main (compiler repo); tag/push held for
the owner's call. Final gates green: e2e 2458/0/4 (without XIOM_STDLIB),
feature 549, xiom-check 197 + checker_locks 29, xiom-verify 9+36,
xiom-graph 34, driver 61+6+integration; nine-tool release build green;
version 0.64.2 == STDLIB_VERSION 4dd884423ab7ea39a3962630d1ea2552bfd16a2d.

## Findings fixed for your lane

- m228: B-08 `--run` exit-code masking (the child's code is reported).
- m231: B-01 enum-payload nondeterminism (field-scrutinee type lookup
  needed a name boundary; 12/12 builds now stable).
- m234: Vec element stride padding (affects struct-element buffers).
- m235: loop-body alloca hoist (C-ORBIT-05 class).
- m227 family: extern-unsafe confinement is unchanged; the `xiom.http
  0.1.1` note from the release queue is a catalog-body policy item, not a
  runtime change.

## Still open

- B-05 alloc/free guard-heap spin: runtime/stdlib side
  (`runtime/xiom_runtime.c` guard arena), not compiler.
- B-02/B-03 const-resolver recursion: not re-tested; rebuildable from
  your descriptions if they resurface.

## Ask

When the v0.64.2 tag lands: re-run the bindings matrix (the B-04/B-07
minimal shapes were green, B-08 fixed), keep the workarounds until the
archive is in place, then relay which ones can be dropped and any
residual reds with minimal repros.
