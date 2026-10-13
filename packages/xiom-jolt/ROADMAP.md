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

## Phase 4 (Planned)
- [ ] Broad-phase queries + collision filtering surface (layers, ray casts)
- [ ] Joint wrappers (hinge/slider/fixed/cone)
- [ ] Character controller
- [ ] Soft bodies
- [ ] Contact events / activation callbacks
- [ ] Deterministic save/restore state helper
- [ ] Re-pin when the drift guard flags a new Jolt tag
