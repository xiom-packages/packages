# xiom.jolt -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 declaration-only bindings (preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored v5.6.0 core
- [x] Generator: mirror + `<Jolt/>` rewriting + 25 per-directory TUs + bridge shim
- [x] Scalar-return bridge: drop + velocity probes (single-threaded job system)
- [x] Suite 4/4 x2 on the m258 compiler build (`--cxx-standard 17`)
- [x] False-positive release-check verdict corrected (bus items -7/-1815)

## Phase 3 (Planned)
- [ ] Broad-phase queries + collision filtering surface
- [ ] Joint wrappers (hinge/slider/fixed/cone)
- [ ] Character controller
- [ ] Soft bodies
- [ ] Deterministic fixed-step helper + save/restore state
- [ ] Re-verify on the m258 archive and close bus item -1815
- [ ] Re-pin when the drift guard flags a new Jolt tag
