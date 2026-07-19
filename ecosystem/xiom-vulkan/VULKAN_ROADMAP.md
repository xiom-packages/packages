# XIOM Vulkan — Production Roadmap (Updated 2026-07-19)

**Compiler:** xiomc v0.48.0 | **Package:** v0.3.0 → v1.0.0 | **Target:** AAA-ready VK bindings

## Current State (Honest Audit)

| Layer | Status | Issues |
|-------|--------|--------|
| `vulkan_extern.xi` | ✅ 755/755 VK functions (100%) | KHR duplicates, no docs |
| `vulkan_safe.xi` | ⚠️ 30 types, **6 CRITICAL bugs** | SF-01 through SF-06 crash at runtime |
| `vulkan_structs.xi` | ✅ 30+ builders, compile-verified | Covers all common create-info types |
| `vulkan_constants_all.xi` | ✅ 3691 constants | Complete |
| C bridge bind modules | ✅ 303 functions across 12 modules | Compile + link verified |
| C bridge legacy | ✅ 117KB, 17 modules | Runtime verified (20-frame test) |
| **Total bridge** | ✅ 332KB, 30 modules | Full VK 1.3 core API |
| AAA readiness | ⚠️ 9/15 PRESENT, 4/15 PARTIAL, 2/15 MISSING | See SAFETY_AUDIT.md |

## Phase 6: FIX SAFETY BUGS — ✅ ALL 12 FIXED (2026-07-19)

All 12 safety bugs (SF-01 through SF-12) fixed. All compile v0.48.0, 11/11 demos link.

## Phase 7: AAA MISSING FEATURES (P1)

| # | Domain | Status |
|---|--------|--------|
| 7.1 | Memory sub-allocator | ✅ **DONE** — `xvk_memory_alloc.c` (305 lines): linear + free-list allocator, 64MB blocks, auto memory type selection |
| 7.2 | Pipeline cache serialization | ✅ **DONE** — `xvk_get_pipeline_cache_data_size`, `xvk_get_pipeline_cache_data`, `xvk_merge_pipeline_caches` in bridge |
| 7.3 | Shader compilation | ✅ **DONE** — `xvk_shader_compile.c` (Phase 7.3): runtime glslc subprocess for GLSL→SPIR-V compilation. High-level API: `shader_compile_glsl()`, `shader_compile_file()` in vulkan.xi |
| 7.4 | Texture loading | PENDING |
| 7.5 | Multi-thread command pools | ✅ **DONE** — Bridge: `xvk_create_command_pools`, `xvk_allocate_command_buffers_multi`, `xvk_queue_submit_multi`, `xvk_get_device_queue2`. Safe: `VulkanQueue` type, `VulkanCommandPool.create_threaded`, `VulkanCommandBuffer.submit_multi`. High-level API: `threaded_command_pool_create()`, `submit_multi_command_buffers()` in vulkan.xi |
| 7.6 | Ray tracing deferred ops | PENDING |

## Phase 8: TOOLING & QA (P2)

| # | Item | Status |
|---|------|--------|
| 8.1 | Debug utils validation layer output capture | PENDING |
| 8.2 | Mouse/keyboard input exposure from GLFW to XIOM | ✅ **DONE** — `get_mouse_pos()`, `is_mouse_down()`, `is_key_down()` in vulkan.xi. Supports WASD, Escape, Space, Left/Right/Middle mouse |
| 8.3 | Font/text rendering module | PENDING |
| 8.4 | CI smoke test suite | ✅ **DONE** — `tests/ci_smoke.xi`: app→buffer→cache→destroy in ~1s |
| 8.5 | Offscreen headless rendering fix | PENDING |

## Bridge Growth

| Version | Size | Added |
|---------|------|-------|
| v0.2.0 (refactor) | 117 KB | Legacy 17 modules |
| v0.2.5 (+bind modules) | 332 KB | 12 bind modules (303 functions) |
| v0.2.7 (+cache) | 333 KB | Pipeline cache serialization |
| v0.2.8 (+memory) | 338 KB | VMA-style memory allocator (305 lines) |
| v0.2.9 (+input) | 339 KB | Mouse/keyboard input (WASD, mouse btn, pos) |
| v0.3.0 (+thread+shaders) | 346 KB | Multi-thread command pools (7.5) + runtime shader compilation (7.3) |
| **v0.3.0 (current)** | **346 KB** | **35 modules, 325+ functions** |

## Compiler Gaps

| ID | Gap | Workaround |
|----|-----|------------|
| CG-01 | Float32/Float64 Vec element reads garbage | Use scalar FFI only |
| CG-02 | E001 Float64 moved value | Separate now() bindings |
| CG-03 | Cross-module use catalog | Multi-file merge |

**All historical GAP-1 through GAP-14: CLOSED (v0.33.0+).**
**Vulkan FFI G1-G7 regression tests: ALL PASS.**
**No new compiler gaps found in this audit.**
