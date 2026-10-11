# AUDIT: xiom.box2d

## Status (2026-10-11)

Vendored-C implementation at 0.3.0. The pre-pilot module (a 56 KB v4-era
static-extern surface expecting struct-by-value FFI plus its demo/safe
satellites) is preserved in git history only; the v3 API is a C handle API,
so the pilot ships a small integer-only bridge instead.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.3 |
| Upstream | Box2D v3.1.1 (tag), vendored unmodified (MIT) |
| Link model | `--c-source` (35 sources + bridge via `port.args.json`); no soname |
| FFI confinement | all `unsafe`/`extern` in the root module `box2d.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 7 checks (real simulation incl. joint motors) |
| Runs | **7/7 x2** on the pin (`scripts/port.ps1`) |

## Design notes

- **Integer-only ABI**: the bridge converts floats to thousandths and keeps
  all struct-by-value traffic (b2WorldDef/b2BodyDef/b2ShapeDef/b2Polygon/
  b2RevoluteJointDef/b2PrismaticJointDef returns) inside C. The XIOM
  boundary sees only ints, pointers into XIOM-owned slots, and result codes.
- **Flat vendor layout**: upstream `src/*.c|h` sit at `vendor/` root and the
  public headers at `vendor/box2d/`, so quoted includes resolve against each
  file's own directory -- the link line needs no `-I` passthrough and the
  vendored bytes stay unmodified (per-file SHA256 table in `SPEC.md` §2).
- Out-param slots are XIOM-owned `Vec[UInt8]` buffers (no malloc/free;
  finding B-05); the signed 32-bit read subtracts 2^32 for negative values.
- **Joint motors (0.3.0)**: the revolute probe hinges a 2.0 x 0.2 bar at the
  origin with gravity off and the motor as the only torque (w settles at the
  motor speed; the joint angle, which Box2D wraps to [-pi, pi], integrates
  to 4 - 2*pi rad); the prismatic probe drives a slider along +x under
  gravity and checks the constraint holds y while the motor translates x.
- No SKIP path: the sources are always compiled in; the suite exercises a
  real resting drop, an impulse->velocity check, and both motor joints on
  every platform.

## Known limitations

- Scope at 0.3.0: version/world/body basics + drop/impulse + revolute and
  prismatic joint motors; broad-phase queries, contact events, remaining
  joint types and callbacks are Phase 3 (`ROADMAP.md`).
- Milli encoding caps precision at 1/1000 units -- sufficient for probe
  assertions, not for general simulation APIs (Phase 3 will expose richer
  wrappers, still through the same confined bridge).
- Windows x64 primary; the vendored path is portable, but no other platform
  has been run yet.
