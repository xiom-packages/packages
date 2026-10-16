# AUDIT: xiom.box2d

## Status (2026-10-15)

Vendored-C implementation at 0.4.0. The pre-pilot module (a 56 KB v4-era
static-extern surface expecting struct-by-value FFI plus its demo/safe
satellites) is preserved in git history only; the v3 API is a C handle API,
so the pilot ships a small integer-only bridge instead.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.5 |
| Upstream | Box2D v3.1.1 (tag), vendored unmodified (MIT) |
| Link model | `--c-source` (35 sources + bridge via `port.args.json`); no soname |
| FFI confinement | all `unsafe`/`extern` in the root module `box2d.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 26 checks (real simulation incl. joint motors, queries, contacts) |
| Runs | **26/26 x2** on the pin (`scripts/port.ps1`) |

## Design notes

- **Integer-only ABI**: the bridge converts floats to thousandths and keeps
  all struct-by-value traffic (b2WorldDef/b2BodyDef/b2ShapeDef/b2Polygon/
  joint defs/returns) inside C. The XIOM boundary sees only ints, pointers
  into XIOM-owned slots (0.3.0 probes), and result codes.
- **Flat vendor layout**: upstream `src/*.c|h` sit at `vendor/` root and the
  public headers at `vendor/box2d/`, so quoted includes resolve against each
  file's own directory -- the link line needs no `-I` passthrough and the
  vendored bytes stay unmodified (per-file SHA256 table in `SPEC.md` §2).
- Probes: out-param slots are XIOM-owned `Vec[UInt8]` buffers (no malloc/free;
  finding B-05); the signed 32-bit read subtracts 2^32 for negative values.
- **Joint motors (0.3.0)**: the revolute probe hinges a 2.0 x 0.2 bar at the
  origin with gravity off and the motor as the only torque (w settles at the
  motor speed; the joint angle, which Box2D wraps to [-pi, pi], integrates
  to 4 - 2*pi rad); the prismatic probe drives a slider along +x under
  gravity and checks the constraint holds y while the motor translates x.
- **Caller surface (0.4.0, engine PACKAGE-ASKS A02)**: pointer-free by
  construction -- world/body/joint registries and every state cache live in
  the bridge, so XIOM reads fresh scalar values through dedicated accessors
  (no out-param slots; B-20/B-24/B-25 discipline).  Body ids are per-world
  monotonic and never reused (stale ids rejected); each world owns a hidden
  static anchor body as the `B2_WORLD` joint side; overlap lists and contact
  events are snapshotted into canonical ascending order for determinism.
  Every bridge shape enables contact/hit events (Box2D defaults them off).
  Contact end events caused by a removal outside a step surface after the
  next step (Box2D swaps its end-event buffers inside `b2World_Step`); the
  suite steps once after removal before asserting.
- No SKIP path: the sources are always compiled in; the suite exercises a
  real resting drop, an impulse->velocity check, motor joints, the world/
  body/step/state flow, broadphase queries and contact events on every
  platform.

## Known limitations

- Scope at 0.4.0: caller 2D-solver surface (world/bodies/step/state/count,
  queries, contacts, revolute/prismatic/weld/distance/wheel/motor joints).
  Edge/chain caller shapes, mouse/filter joints, sensors, snapshots and
  sample scenes are Phase 5 (`ROADMAP.md`).
- Milli encoding caps precision at 1/1000 units -- sufficient for the suite
  assertions and the engine contract v0 adapter flow, not for lossless
  simulation APIs.
- Deterministic single-threaded worlds only (Box2D `workerCount` stays 1);
  no threading surface.
- Windows x64 primary; `runtime_deps: []` (compile-class package); the
  vendored path is portable but no other platform has been run yet.
