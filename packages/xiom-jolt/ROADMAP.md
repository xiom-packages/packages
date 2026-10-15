# xiom.jolt -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 declaration-only bindings (preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored v5.6.0 core
- [x] Generator: mirror + `<Jolt/>` rewriting + 25 per-directory TUs + bridge shim
- [x] Scalar-return bridge: drop + velocity probes (single-threaded job system)
- [x] Suite 4/4 x2 on the m258 compiler build (`--cxx-standard 17`)
- [x] False-positive release-check verdict corrected (bus items -7/-1815)

## Phase 3 (Done) -- 0.3.0 caller-usable world/body surface
- [x] World registry: create/destroy with gravity + fixed dt + capacity
      (slot handles, no pointer crossing -- B-25)
- [x] Body lifecycle: add(desc) -> id, remove, count; BOX + SPHERE with
      extents/mass/position/rotation/static-dynamic inputs
- [x] Step control: `jolt_step` / `jolt_step_n` (explicit fixed dt, no wall
      clock); state readable between steps
- [x] Owned state read-back by id: position 3, rotation 4, velocity 3, awake
      (bridge-owned scalar cache; no out-param slots)
- [x] Engine contract v0 flow covered by the suite (+14 checks, 18 total)
- [x] Manifest `modules:` + PROVENANCE.md retrofit at this touch

## Phase 4 (Done) -- 0.4.0 external force/torque input
- [x] `jolt_body_apply_force` / `jolt_body_apply_torque`: owned scalar args
      (milli N / milli N.m), center-of-mass application for the next step
- [x] One-step-only semantics: Jolt clears accumulated force/torque after
      every Update (repeated calls before a step accumulate); input wakes
      sleeping bodies (EActivation::Activate); static bodies are a no-op
- [x] Angular velocity added to the owned state read-back (wx/wy/wz_milli,
      bridge-owned scalar cache -- still no out-param slots)
- [x] Unknown/removed ids rejected with the typed `kErrBadBody` error
- [x] Engine buoyancy/water ask (REL-20261013-2115-engine) covered by the
      suite (+6 checks, 24 total)

## Phase 5 (In progress) -- engine E-family
- [x] 0.5.0 **E1 world queries**: raycast (closest + any-hit), sphere/capsule
      closest sweeps, sphere/capsule overlap lists; owned `JoltQueryHit`
      (flag/body/position/normal/fraction); deterministic broadphase order
      (canonical ascending body id; tested across fresh worlds)
- [x] 0.5.0 **E2 capsule shape**: `JOLT_SHAPE_CAPSULE` bodies (radius + half
      height of the segment) settle/contact and take part in E1 queries
- [x] 0.5.0 **E7 contacts + sensors**: last-step contact manifolds (pair,
      points, normal, penetration depth) and non-physical sensor volumes
      with per-step overlap events; typed errors for unknown/removed ids
- [x] 0.6.0 **E3 typed joints**: fixed/hinge/slider/point joints between two
      bodies or body-world (`JOLT_WORLD`); world-space anchors/axes; motors
      (velocity/position targets) configured per joint; limits (min/max
      angle/translation, validated against Jolt's ranges); owned state
      read-back (hinge angle / slider position + applied impulse); typed
      errors (bad ids, unsupported combos, invalid limits); joint-driven
      determinism covered by the suite (motorized hinge angle bit-identical
      across repeated runs)
- [x] 0.6.0 **E6 convex/compound bodies**: convex hull bodies from a
      caller-owned Vec of milli xyz triples (4..256 vertices, interior
      points allowed); compound bodies combining box/sphere/capsule/convex
      parts at relative transforms (flat `JOLT_PART_STRIDE` table + shared
      vertex buffer); both settle/sleep and are queryable through E1 + E7
- [ ] **E4** character controller -- remains
- [ ] **E5** soft bodies -- remains
- [ ] Deterministic save/restore state helper -- remains
- [ ] Collision filtering surface (layers/masks on query paths)
- [ ] Re-pin when the drift guard flags a new Jolt tag
