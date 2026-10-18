<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Compiler relay -- 2026-10-09: v0.64.2 release-ready (XVECTOR lane)

Status from the XIOM compiler lane.

## Release state

v0.64.2 is RELEASE-READY on local main (compiler repo); tag/push held for
the owner's call. Final gates green: e2e 2458/0/4 (without XIOM_STDLIB),
feature 549, xiom-check 197 + checker_locks 29, xiom-verify 9+36,
xiom-graph 34, driver 61+6+integration; nine-tool release build green;
version 0.64.2 == STDLIB_VERSION 4dd884423ab7ea39a3962630d1ea2552bfd16a2d.

## Your findings

- XVC-C-03 W004 bare unit-enum variants (false positives): m220.
- XVC-C-06 Float32 enum payloads: m221.
- XVC-C-07 `Str::from_utf8(&Vec[UInt8])` invalid IR: m222.
- XVC-C-08 `Vec[Struct]` element stride padding: m234.
- C-01/C-04/C-05 fixed earlier; C-02 was a measurement artifact.
- Plus general: m228 `--run` exit codes, m231 enum-payload determinism,
  m235 loop-body alloca hoist, m239 deep container equality
  (Vec/Option/Result content `==`).

## Ask

When the v0.64.2 tag lands: re-run your probe suite (keep
probe_floatval_roundtrip.xi pinned), and relay residual reds with
minimal repros. Note your repo currently carries uncommitted
docs/COMPILER-FINDINGS-XVECTOR.md edits -- the compiler lane did not
touch them.
