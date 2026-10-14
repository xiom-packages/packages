# AUDIT: xiom.jolt

## Status (2026-10-14)

Vendored C++ implementation at 0.4.0, **verified on the pinned v0.64.4
toolchain** (`--cxx-standard 17`; the m258 flag now ships in the official
pin, so the m258 gate that parked 0.2.0 is closed).  Jolt requires real
C++17; the flag and the 26-source list are threaded into `port.args.json`.

| Item | State |
|------|-------|
| Compiler | v0.64.4 (official pin; `--cxx-standard 17`) |
| Upstream | JoltPhysics tag **v5.6.0** (tarball sha256 `6E069EE0...`, 19.4 MB) |
| Generator | `tools/combine.py` -- mirrors `Jolt/**` (`<Jolt/...>` -> `"Jolt/..."`), 25 per-directory TUs + a bridge shim at the vendor root; tree sha256 `ea20c2d1f1f2a16e1fa62efeff5804c9d7b47f51812eefb8ed9ddb4330d6b69b` (re-verified read-only 2026-10-13; untouched by 0.4.0) |
| Bridge | `src/jolt_bridge.cpp` via the generated `vendor/jolt_bridge.cpp` shim: probes (drop/impulse) + a 4-slot world registry with body add/remove/count, per-body apply_force/apply_torque, step/step_n, and a bridge-owned state cache (position/rotation/linear+angular velocity); single-threaded job system; integer-only ABI |
| Suite | `tests/test_conformance.xi`, 24 checks |
| Runs | **24/24 x2** on v0.64.4: 0.2.0 probes (drop settles at 479 milli, body asleep; impulse vx=4995) + world lifecycle, engine flows (box/sphere), between-step read-back, body add/remove/count, rotation round-trip, determinism, and the 0.4.0 force/torque checks (60 N on 1 kg -> vx ~1 m/s in one step, no re-acceleration after the step; 6 N.m about z -> wz ~0.6 rad/s; unknown/removed ids rejected) |
| Manifest | `modules: ["xiom.jolt"]` + `PROVENANCE.md` retrofitted at the 0.3.0 touch (fleet -1721-2 / upstream-first) |
| History | The v0.64.3 release-check "if constexpr probe green -> unblocked" verdict was a false positive (clang accepts constexpr if as a C++14 extension); corrected via bus items `REL-20261010-1815-bindings` / `-7`.  Jolt 0.2.0 shipped in `eco-v0.1.161`; 0.3.0 shipped in `eco-v0.1.176`; 0.4.0 external force/torque input is the engine buoyancy ask (REL-20261013-2115-engine). |

## Design notes

- One generated shim TU at the vendor root compiles the reviewable bridge
  from `src/`; the quoted `"Jolt/..."` includes resolve through the
  compiler's include stack (the xiom link line has no `-I` passthrough).
- The bridge uses `JobSystemSingleThreaded` -- deterministic, no worker
  threads.  Fixed `dt` only; no wall clock is read anywhere.
- World handles are registry slots (0..3), body ids are Jolt's packed
  index+sequence numbers: no raw pointer crosses the boundary (B-25), stale
  ids are rejected by lookup, and each world's lifetime owns its
  PhysicsSystem/allocator/filters (destroyed in reverse declaration order).
- Scalar returns only; body state is cached into bridge-owned scalars and
  fetched as scalars -- no out-param slots, no foreign-pointer reads
  (B-20/B-23/B-24 discipline).
- Registration (RegisterDefaultAllocator + Factory + RegisterTypes) is
  ref-counted so probes and live worlds share it safely.

## Re-verification procedure

1. Regenerate: `python tools/combine.py <upstream-root> vendor` (the sparse
   clone/tarball recipe is in `SPEC.md`; clone hygiene in `PROVENANCE.md`).
2. `scripts/port.ps1 -Package xiom.jolt -TimeoutSec 600` (26 TUs) x2 on the
   pinned v0.64.4 toolchain.
3. Record `STATUS.json` with the feat commit sha; keep the `platforms` /
   `runtime_deps` fields (they are part of the platform-matrix
   declaration).
