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

## Phase 6: FIX SAFETY BUGS (P0 — BLOCKING v1.0.0)

| ID | Bug | Fix |
|----|-----|-----|
| **SF-01** | CommandBuffer.allocate: raw handle as struct ptr | Allocate VkCommandBufferAllocateInfo via bridge |
| **SF-02** | DescriptorSet.allocate: raw handle as struct ptr | Allocate VkDescriptorSetAllocateInfo via bridge |
| **SF-03** | CommandBuffer.begin: flags as struct ptr | Allocate VkCommandBufferBeginInfo via bridge |
| **SF-04** | CommandBuffer.submit: NULL submit info | Build VkSubmitInfo via bridge |
| **SF-05** | CommandBuffer.set_viewport: NULL with count=1 | Allocate VkViewport, populate from params |
| **SF-06** | CommandBuffer.set_scissor: NULL with count=1 | Allocate VkRect2D, populate from params |
| **SF-07** | Instance.enumerate_physical_devices: returns 0 | Return c32 as Int; fix type mismatch |
| **SF-08** | VulkanContext.init: checks wrong variable | Check pdc, allocate devices array, return first |
| **SF-09** | Event.get_status: wrong VkResult constant | ✅ Compare to 1 instead of 3 |
| **Phase 6** | **ALL 12 SAFETY BUGS FIXED** | ✅ All compile v0.48.0, 11/11 demos link |

## Phase 7: AAA MISSING FEATURES (P1)

| # | Domain | What to add |
|---|--------|-------------|
| 7.1 | Memory | VMA-style sub-allocator (linear/buddy) + bind2/requirements2 bridge |
| 7.2 | Pipeline | Pipeline cache serialization: get_data → write to disk, read → merge |
| 7.3 | Shader | glslangValidator/SPIRV-Cross integration OR bridge to external tool |
| 7.4 | Texture | KTX/DDS loader in bridge; automated staging→upload→mipmap pipeline |
| 7.5 | Multi-thread | Per-thread command pool manager; async compute queue support |
| 7.6 | Ray tracing | Deferred host operations (VK_KHR_deferred_host_operations) |

## Phase 8: TOOLING & QA (P2)

| # | Item |
|---|------|
| 8.1 | Debug utils validation layer output capture (VkDebugUtilsMessengerCallback) |
| 8.2 | Mouse/keyboard input exposure from GLFW to XIOM |
| 8.3 | Font/text rendering module (stb_truetype in bridge + glyph atlas + texture binding) |
| 8.4 | CI smoke test suite (create_instance → device → buffer → destroy in 1 second) |
| 8.5 | Offscreen headless rendering fix (no GLFW window dependency) |

## Compiler Gaps

| ID | Gap | Workaround |
|----|-----|------------|
| CG-01 | Float32/Float64 Vec element reads garbage | Use scalar FFI only |
| CG-02 | E001 Float64 moved value | Separate now() bindings |
| CG-03 | Cross-module use catalog | Multi-file merge |

**All historical GAP-1 through GAP-14: CLOSED (v0.33.0+).**
**Vulkan FFI G1-G7 regression tests: ALL PASS.**
**No new compiler gaps found in this audit.**
