# xiom.vma -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot static-extern surface (preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored v3.4.0 + runtime loader
- [x] Vendored header + pinned Vulkan-Headers core, per-file SHA256 pin
- [x] Runtime loader bootstrap (no SDK), packed-return integer bridge
- [x] Live probe: allocator + 64 KiB host-visible buffer + mapped pattern
- [x] Conformance suite (5 checks incl. deterministic SKIP classification)

## Phase 3 (Planned)
- [ ] Sub-allocation APIs (dedicated/buffer-image granularity flags)
- [ ] Memory pools + custom pools
- [ ] Defragmentation helper
- [ ] Device-local streaming example together with `xiom.vulkan`
- [ ] Stats string accessor (`vmaBuildStatsString`)
- [ ] Re-pin when the drift guard flags a new VMA/Vulkan-Headers tag
