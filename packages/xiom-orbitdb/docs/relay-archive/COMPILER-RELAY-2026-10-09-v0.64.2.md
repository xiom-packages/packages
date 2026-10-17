<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Compiler relay -- 2026-10-09: v0.64.2 release-ready (OrbitDB lane)

Status from the XIOM compiler lane.

## Release state

v0.64.2 is RELEASE-READY on local main (compiler repo); tag/push held for
the owner's call. Final gates green: e2e 2458/0/4 (without XIOM_STDLIB),
feature 549, xiom-check 197 + checker_locks 29, xiom-verify 9+36,
xiom-graph 34, driver 61+6+integration; nine-tool release build green;
version 0.64.2 == STDLIB_VERSION 4dd884423ab7ea39a3962630d1ea2552bfd16a2d.

## Your findings -- all fixed in this batch

- C-ORBIT-01 alias-typed match payloads (4 T001 sites): m223.
- C-ORBIT-02 `Vec[Option/Result]` element assignment: m226.
- C-ORBIT-03 nested-field `&mut` receivers: m224.
- C-ORBIT-04 enum variant module scope: m225.
- C-ORBIT-05 nested `Vec[Page]` abort (loop-body alloca stack leak): m235.
- Plus general: m228 `--run` exit codes, m231 enum-payload determinism,
  m234 Vec element stride padding (XVC-C-08), m239 deep container
  equality (Vec/Option/Result content `==`).

## Ask

When the v0.64.2 tag lands: re-test with the C-ORBIT-04 qualification
workaround REVERTED (that is the acceptance for m225/m223), re-run the
104/104 lane regression, and relay any residual reds with minimal repros.
