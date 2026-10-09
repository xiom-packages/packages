# xiom.box2d -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot v4-era static-extern surface + demo (preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored v3.1.1
- [x] Vendored flat layout (35 C sources + public headers), per-file SHA256 pin
- [x] Integer-only bridge: version, gravity, resting drop, impulse -> velocity
- [x] Conformance suite (5 checks incl. real stepping simulation)

## Phase 3 (Planned)
- [ ] Body/joint wrappers beyond the drop scenario (revolute/prismatic/weld/mouse)
- [ ] Broad-phase queries + contact events (callbacks via the bridge)
- [ ] World snapshot / recording replay
- [ ] Sensor + mover helpers
- [ ] Sample scene example (`examples/`) driven by the suite
- [ ] Re-pin to the latest v3.x tag when the drift guard flags it
