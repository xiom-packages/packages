# xiom.box2d -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot v4-era static-extern surface + demo (preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored v3.1.1
- [x] Vendored flat layout (35 C sources + public headers), per-file SHA256 pin
- [x] Integer-only bridge: version, gravity, resting drop, impulse -> velocity
- [x] Conformance suite (5 checks incl. real stepping simulation)

## Phase 3 (Done) -- 0.3.0 joints with motors
- [x] Revolute + prismatic joints with motors (motor-driven rotor + gravity-held slider; wrapped-angle semantics pinned)
- [x] Conformance suite grown to 7 checks (fixed scenarios stay as conformance probes)

## Phase 4 (Done) -- 0.4.0 caller 2D-solver surface (engine PACKAGE-ASKS A02)
- [x] World create/destroy (2D gravity, fixed dt, body capacity), dt readback
- [x] Static + dynamic bodies with caller shapes (circle/box), positions, angles, mass override, removal, count
- [x] Step / step N at the world's fixed dt (4 Box2D sub-steps)
- [x] State read by handle (pos/vel/angle/angular velocity/awake) via dedicated accessors building fresh values (no out-param slot recycle)
- [x] Broadphase queries: closest raycast + circle/box overlap lists (canonical ascending body id)
- [x] Contact events: begin/end/hit with point/normal/approach speed (events enabled on every bridge shape)
- [x] Remaining tractable joint types through one typed desc: revolute, prismatic, weld, distance, wheel, motor (hidden per-world anchor = the world side)
- [x] Typed error matrix (bad handles/ids/indices/kinds)
- [x] Conformance suite 7 -> 26 checks (A02 probes: world/body/state/step, queries, contacts, joints)

## Phase 5 (Next)
- [ ] Edge/chain caller shapes (staged per A02; `b2CreateSegmentShape`/`b2CreateChain`)
- [ ] Mouse + filter joints; sensor helpers (sensor events exist upstream)
- [ ] World snapshot / recording replay
- [ ] Sample scene example (`examples/`) driven by the suite
- [ ] Re-pin to the latest v3.x tag when the drift guard flags it
