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

## Phase 4 (Done) -- 0.3.0 full top-level surface (SDK 100% program, slice B3)
- [x] Oracle parse of the SDK header (72 top-level `vma*` functions; generator
      `tools/gen_vma_full.py`, no manual lists)
- [x] Generated C++ bridge with one wrapper per function + export table +
      link proof + null-argument guards (`src/vma_full_bridge.cpp`; composes
      the unchanged `src/vma_bridge.cpp`)
- [x] Typed XIOM family modules (10) + raw bound surface + RHI helpers
      (`src/vma_full_*.xi`); `bound=72/72`
- [x] Config-gated functions enabled and bridged:
      `vmaImportVulkanFunctionsFromVolk` (vendored volk) and
      `vmaGetMemoryWin32Handle` (vendored `vulkan_win32.h`)
- [x] Full-surface suite: RHI path (allocator -> buffer -> info -> destroy ->
      teardown), null-argument error path, SKIP classification (21/21 x2)
- [x] `docs/COVERAGE.md` (oracle vs bound vs resolved + non-FFI notes) and
      `PROVENANCE.md` (upstream tags/pins, derived vs independent)

## Phase 5 (Next)
- [ ] Enums/flags as generated `pub const` constants module (DoD constant count)
- [ ] Device-local streaming example together with `xiom.vulkan`
- [ ] Re-pin when the drift guard flags a new VMA/Vulkan-Headers tag
