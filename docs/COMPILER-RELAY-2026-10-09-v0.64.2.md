<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Compiler relay -- 2026-10-09: v0.64.2 release-ready (packages lane)

Status from the XIOM compiler lane, for the packages lane (PULSE /
ORBITDB / XVECTOR probes ride the same compiler).

## Release state

v0.64.2 is RELEASE-READY on local main (compiler repo); tag/push held for
the owner's call. Final gates green: e2e 2458/0/4 (without XIOM_STDLIB),
feature 549, xiom-check 197 + checker_locks 29, xiom-verify 9+36,
xiom-graph 34, driver 61+6+integration; nine-tier release build green;
version 0.64.2 == STDLIB_VERSION 4dd884423ab7ea39a3962630d1ea2552bfd16a2d.

## Findings fixed for your lane in the v0.64.2 batch

- m228: `--run` exits with the program's code (B-08).
- m229: packages `is Ok(<literal>)` lowering.
- m230/m236: user-module import chains now load the stdlib catalog
  prelude (the `xiom.encoding`-via-user-module hard fail).
- m231: field-scrutinee type lookup name boundary (B-01 enum-payload
  nondeterminism; 12/12 stable).
- m232: installer home unification (C-PULSE-13).
- m234: Vec element stride padding (XVC-C-08).
- m235: loop-body alloca stack leak (C-ORBIT-05).
- m237/m238: array_zip truncate + zero-length fixed arrays by value.
- m239: deep container equality -- **your `res_eq` probe
  (tmp/sweep2/pkg/res_eq.xi) now exits 0**: `Ok(Vec)` payload content is
  compared recursively, Vec[Int]/Vec[Str] content equality is real.
  Map/Set content equality is the one documented remaining gap.
- m241: OOB Vec index WRITE now traps under `--overflow-checks`.

## Still open (compiler lane)

- Triplicate sibling exports break alias-qualified calls (wave-97 stdlib
  finding, reproduced on v0.64.2; next batch).
- Map/Set `==` content equality (design documented, not implemented).

## Ask

When the v0.64.2 tag lands: re-run the packages matrix (incl. the
res_eq acceptance probe and any C-PULSE/C-ORBIT workaround sets) on it,
revert obsolete workarounds, and relay residual reds with minimal repros.
