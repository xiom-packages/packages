# AUDIT: xiom.jolt

## Status (2026-10-14)

Vendored C++ implementation at 0.6.0, **verified on the pinned v0.64.4
toolchain** (`--cxx-standard 17`; the m258 flag now ships in the official
pin, so the m258 gate that parked 0.2.0 is closed).  Jolt requires real
C++17; the flag and the 26-source list are threaded into `port.args.json`.

| Item | State |
|------|-------|
| Compiler | v0.64.4 (official pin; `--cxx-standard 17`) |
| Upstream | JoltPhysics tag **v5.6.0** (tarball sha256 `6E069EE0...`, 19.4 MB) |
| Generator | `tools/combine.py` -- mirrors `Jolt/**` (`<Jolt/...>` -> `"Jolt/..."`), 25 per-directory TUs + a bridge shim at the vendor root; tree sha256 `ea20c2d1f1f2a16e1fa62efeff5804c9d7b47f51812eefb8ed9ddb4330d6b69b` (re-verified read-only 2026-10-13; untouched by 0.4.0/0.5.0/0.6.0) |
| Bridge | `src/jolt_bridge.cpp` via the generated `vendor/jolt_bridge.cpp` shim: probes (drop/impulse) + a 4-slot world registry with body add/remove/count (box/sphere/capsule/sensor/convex/compound), per-body apply_force/apply_torque, step/step_n, a bridge-owned state cache, world queries (raycast closest/any, sphere/capsule closest sweep, sphere/capsule overlap with canonical order), a per-step contact/sensor cache fed by a ContactListener, and a typed joint registry with motors/limits/state read-back (`Ref<Constraint>` per joint, body-world via `Body::sFixedToWorld`); single-threaded job system; integer-only ABI |
| Suite | `tests/test_conformance.xi`, 109 checks |
| Runs | **109/109 x2** on v0.64.4: 0.2.0 probes (drop settles at 479 milli, body asleep; impulse vx=4995) + world lifecycle, engine flows (box/sphere/capsule), between-step read-back, body add/remove/count, rotation round-trip, determinism, the 0.4.0 force/torque checks, the 0.5.0 tiers (E1 raycast/sweep/overlap with canonical order + cross-world bit-identical repeats, E2 capsule settle/rotation/query participation, E7 contact manifolds + sensor events) and the 0.6.0 tiers: E3 typed joints (motorized hinge reaches 999 milli rad in 60 steps and repeats bit-identically; position motor 699 vs target 700; limits clamp at exactly 250/200; weld under gravity holds + reaction impulse 163357 milli; point pivot holds; typed errors and body-removal auto-cleanup) and E6 convex/compound (hull + 4-part compound settle at 479 milli asleep, repeat bit-identically, are hit per part by raycasts, and report landing contacts) |
| Manifest | `modules: ["xiom.jolt"]` + `PROVENANCE.md` retrofitted at the 0.3.0 touch (fleet -1721-2 / upstream-first) |
| History | The v0.64.3 release-check "if constexpr probe green -> unblocked" verdict was a false positive (clang accepts constexpr if as a C++14 extension); corrected via bus items `REL-20261010-1815-bindings` / `-7`.  Jolt 0.2.0 shipped in `eco-v0.1.161`; 0.3.0 shipped in `eco-v0.1.176`; 0.4.0 external force/torque input (engine buoyancy ask REL-20261013-2115-engine) shipped in `eco-v0.1.179`; 0.5.0 (engine REL-20261014-1510-engine, tiers E1/E2/E7) is recorded; 0.6.0 (same engine family, tiers E3/E6) is current. |

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
- Scalar returns only; body state, query hits, overlap lists, contacts and
  sensor events are cached into bridge-owned slots and fetched as scalars --
  no out-param slots, no foreign-pointer reads (B-20/B-23/B-24 discipline).
  The bridge keeps POD global state only (no non-trivial globals).
- Temporary query shapes are owned by `RefConst<Shape>`: a freshly `new`ed
  Jolt `Shape` starts at refcount 0, so a manual `Release()` asserts "Too
  many calls to Release" (the JPH_ASSERT is live -- the C++ build runs with
  asserts enabled).  RefConst AddRef's on construction and deletes on scope
  exit (found and fixed during 0.5.0 bring-up).
- Constraints (0.6.0) are owned by a per-world `Ref<Constraint>` registry
  and registered in the `PhysicsSystem` with raw pointers; teardown keeps
  the order safe at every exit: `joltb_body_remove` removes the body's
  joints first (`RemoveConstraint` then release), `joltb_joint_remove`
  mirrors that, and `joltb_world_destroy` unregisters every constraint
  before the world is deleted.  Body-world joints use Jolt's
  `Body::sFixedToWorld` sentinel; the XIOM side only ever sees the `-1`
  handling constant.  Hull/part vertex data is copied into bridge-owned
  shapes per call, so caller `Vec` buffers are borrowed for the call only.
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
