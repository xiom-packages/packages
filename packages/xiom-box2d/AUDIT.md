# AUDIT: xiom.box2d

## Status (2026-10-09)

Vendored-C implementation at 0.2.0. The pre-pilot module (a 56 KB v4-era
static-extern surface expecting struct-by-value FFI plus its demo/safe
satellites) is preserved in git history only; the v3 API is a C handle API,
so the pilot ships a small integer-only bridge instead.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.2 |
| Upstream | Box2D v3.1.1 (tag), vendored unmodified (MIT) |
| Link model | `--c-source` (35 sources + bridge via `port.args.json`); no soname |
| FFI confinement | all `unsafe`/`extern` in the root module `box2d.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 5 checks (real simulation) |
| Runs | 5/5 on the pin (see the session relay for the recorded matrix) |

## Design notes

- **Integer-only ABI**: the bridge converts floats to thousandths and keeps
  all struct-by-value traffic (b2WorldDef/b2BodyDef/b2ShapeDef/b2Polygon
  returns) inside C. The XIOM boundary sees only ints, pointers into
  XIOM-owned slots, and result codes.
- **Flat vendor layout**: upstream `src/*.c|h` sit at `vendor/` root and the
  public headers at `vendor/box2d/`, so quoted includes resolve against each
  file's own directory -- the link line needs no `-I` passthrough and the
  vendored bytes stay unmodified (per-file SHA256 table in `SPEC.md` §2).
- Out-param slots are XIOM-owned `Vec[UInt8]` buffers (no malloc/free;
  finding B-05); the signed 32-bit read subtracts 2^32 for negative values.
- No SKIP path: the sources are always compiled in; the suite exercises a
  real resting drop and an impulse->velocity check on every platform.

## Known limitations

- Pilot scope: version/world/body basics + drop/impulse; joints, events,
  broad-phase queries and callbacks are Phase 2 (`ROADMAP.md`).
- Milli encoding caps precision at 1/1000 units -- sufficient for probe
  assertions, not for general simulation APIs (Phase 2 will expose richer
  wrappers, still through the same confined bridge).
- Windows x64 primary; the vendored path is portable, but no other platform
  has been run yet.
