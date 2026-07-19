# XIOM Vulkan — Production Roadmap

**Date:** 2026-07-19  
**Compiler:** xiomc v0.48.0 — 495+ tests, zero warnings  
**Package:** ecosystem/xiom-vulkan v0.3.0 (target: v1.0.0)

## Current State

| Layer | Status | Validation |
|-------|--------|------------|
| `vulkan_extern.xi` — 755 VK function declarations | ✅ 100% VK 1.3 core + extensions | Compiles v0.48.0 |
| `vulkan_safe.xi` — 29 resource types | ✅ 29/29 with contracts | Compiles v0.48.0 |
| `vulkan_structs.xi` — struct builders | ⚠️ 6 builders, 30+ needed | Partial |
| `vulkan_constants_all.xi` — 3691 constants | ✅ Compiles | Verfied v0.48.0 |
| C bridge legacy (17 modules, 117KB) | ✅ Runtime verified (20-frame test, exit 0) | GPU: RTX 3070 Ti |
| C bridge bind modules (12 modules, ~200KB) | ✅ Compile + link + runs | Runtime smoke passed |
| **Total bridge** (30 modules) | **✅ 332KB, runtime verified** | **Full VK 1.3 core API** |
| 11 demos | ⚠️ 6 working, 5 need fixes | Compile+link passes |

## Phase 1: STABILIZE (current)

| # | Item | Priority | Agent |
|---|------|----------|-------|
| 1.1 | Fix auto-close in demos — window must stay open until user closes | **P0** | Agent |
| 1.2 | Fix build.ps1 for multi-module bridge compilation | **P0** | Manual |
| 1.3 | Restore all 11 demos to working state | **P0** | Agent |
| 1.4 | Remove all agent artifacts + cleanup bridge directory | **P0** | Manual |
| 1.5 | Runtime smoke test: 60s demo run, verify no crash | **P0** | Manual |

## Phase 2: VERIFY BIND MODULES

| # | Item | Priority | Agent |
|---|------|----------|-------|
| 2.1 | Write XIOM probe for xvk_structs (alloc → write → read → free → no crash) | **P1** | Agent |
| 2.2 | Write XIOM probe for xvk_bind_instance (create_instance → physical device → destroy) | **P1** | Agent |
| 2.3 | Write XIOM probe for xvk_bind_device (create_device → get_queue → destroy) | **P1** | Agent |
| 2.4 | Write XIOM probe for xvk_bind_buffer (create_buffer → allocate_memory → bind → map → unmap → destroy) | **P1** | Agent |
| 2.5 | Write XIOM probe for xvk_bind_image (create_image → memory → view → sampler → destroy) | **P1** | Agent |
| 2.6 | Write XIOM probe for xvk_bind_pipeline (shader_module → layout → graphics_pipeline) | **P1** | Agent |
| 2.7 | Write XIOM probe for xvk_bind_descriptor (set_layout → pool → allocate → update → bind) | **P1** | Agent |
| 2.8 | Write XIOM probe for xvk_bind_command (pool → allocate → begin → draw → end → submit) | **P1** | Agent |
| 2.9 | Write XIOM probe for xvk_bind_swapchain (surface_query → create → acquire → present) | **P2** | Agent |
| 2.10 | Write XIOM probe for xvk_bind_query (pool → begin → end → get_results) | **P2** | Agent |
| 2.11 | Write XIOM probe for xvk_bind_sync (fence → semaphore → event → timeline) | **P2** | Agent |

## Phase 3: STRUCT BUILDERS

| # | Item | Priority | Agent |
|---|------|----------|-------|
| 3.1 | Verify existing builders in vulkan_structs.xi compile | **P1** | Agent |
| 3.2 | Add 30+ create-info builders (see BRIDGE_AUDIT.md list) | **P1** | Agent |
| 3.3 | Verify each builder with xiom MCP diagnostics | **P1** | Agent |
| 3.4 | Port vulkan_safe.xi all 29 types to use struct builders | **P2** | Agent |

## Phase 4: DEMOS & TOOLING

| # | Item | Priority | Agent |
|---|------|----------|-------|
| 4.1 | Write 11 clean demos (no agent corruption) | **P1** | Agent |
| 4.2 | Add text rendering module (stb_truetype in bridge) | **P2** | Agent |
| 4.3 | Add mouse/keyboard input exposure to XIOM | **P2** | Agent |
| 4.4 | Fix compute/test demos (no offscreen hang) | **P2** | Agent |
| 4.5 | Add debug utils validation layer output capture | **P2** | Agent |
| 4.6 | Write comprehensive CI test suite (spec or smoke) | **P2** | Agent |

## Phase 5: DOCS & RELEASE

| # | Item | Priority | Agent |
|---|------|----------|-------|
| 5.1 | Write GETTING_STARTED.md (first-time setup + demo run) | **P2** | Agent |
| 5.2 | Write API_REFERENCE.md (every xvk_* function documented) | **P2** | Agent |
| 5.3 | Final audit: compile every .xi file with xiomc v0.48.0 diagnostics | **P2** | Manual |
| 5.4 | Tag v1.0.0 | **P2** | Manual |

## Compiler Gaps (xiomc v0.48.0)

| Gap | Status | Workaround |
|-----|--------|------------|
| Float32 Vec element reads (G4) | ⚠️ Reproduced v0.48 | Use Float32 scalar FFI only |
| E001 Float64 "use of moved value" | ⚠️ Cosmetic | Use separate `now()` bindings per use |
| Cross-module `use xiom.*` catalog | ⚠️ Multi-file merge works | Pass all .xi files on xiomc command line |

All historical GAP-1 through GAP-14: ✅ CLOSED (v0.33.0+).  
Vulkan FFI G1-G7 regression tests: ✅ ALL PASS (feature_regression_tests.rs).

## Agent Instructions

All agents MUST:
1. Run `xiomc --diagnostics=json <file.xi>` before marking any file complete
2. Verify zero `T001` type errors and zero `P001` parse errors
3. Use `xiom_check_xiom_syntax` tool for quick syntax validation
4. Use `xiom_compile_and_analyze` for full builds with diagnostics output
5. Report any new compiler gaps to `ecosystem/COMPILER_GAPS.md`
6. Do NOT modify bridge C files unless explicitly asked
7. Only write in `ecosystem/xiom-vulkan/` directory
