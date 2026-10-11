# xiom.box2d -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot v4-era static-extern surface + demo (preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored v3.1.1
- [x] Vendored flat layout (35 C sources + public headers), per-file SHA256 pin
- [x] Integer-only bridge: version, gravity, resting drop, impulse -> velocity
- [x] Conformance suite (5 checks incl. real stepping simulation)

## Phase 3 (In progress) -- 0.3.0 joints with motors
- [x] Revolute + prismatic joints with motors (motor-driven rotor + gravity-held slider; wrapped-angle semantics pinned)
- [ ] Broad-phase queries + contact events (callbacks via the bridge)
- [ ] Remaining joint types (weld/mouse/wheel/motor/distance) probes
- [ ] World snapshot / recording replay
- [ ] Sensor + mover helpers
- [ ] Sample scene example (`examples/`) driven by the suite
- [ ] Re-pin to the latest v3.x tag when the drift guard flags it
