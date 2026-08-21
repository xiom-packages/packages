# xiom-vulkan -- Production Safety Audit & AAA Readiness Report

**Date:** 2026-07-19 | **Compiler:** xiom v0.48.0 | **Package:** v0.3.0 -> v1.0.0

## Executive Summary

**The Vulkan API bindings are 100% complete** -- 755 VK functions across all extensions, 303 bridge functions, 30 safe types, 30+ struct builders. **However, the safe wrapper layer has 6 CRITICAL bugs** that will crash at runtime, and 6 out of 15 AAA engine domains are only PARTIAL. The package is a production-grade Vulkan FFI layer, NOT a complete game engine. For AAA production use, the binding layer itself is ready; the tooling pipeline (shader compilation, texture loading, memory sub-allocation) must be built on top.

---

## 1. SAFETY AUDIT -- vulkan_safe.xi

### CRITICAL (will crash at runtime) -- 6 bugs

| ID | Function | Line | Bug | Fix |
|----|----------|------|-----|-----|
| **SF-01** | `CommandBuffer.allocate` | 784 | Passes raw `pool` handle as `VkCommandBufferAllocateInfo*` struct pointer | Must allocate `VkCommandBufferAllocateInfo` via bridge, write `pool` + `level` fields |
| **SF-02** | `DescriptorSet.allocate` | 977 | Passes raw `pool` handle as `VkDescriptorSetAllocateInfo*` struct pointer | Must allocate `VkDescriptorSetAllocateInfo` via bridge, write `pool` + `layout` fields |
| **SF-03** | `CommandBuffer.begin` | 799 | Passes `flags` (Int32) as `VkCommandBufferBeginInfo*` struct pointer | Must allocate `VkCommandBufferBeginInfo` and write sType+pNext+flags |
| **SF-04** | `CommandBuffer.submit` | 817 | Passes NULL for `VkSubmitInfo*` array -- nothing is submitted | Must build `VkSubmitInfo` with command buffer handle, semaphores |
| **SF-05** | `CommandBuffer.set_viewport` | 837 | All 6 params discarded, passes NULL viewports with count=1 (undefined behavior) | Must allocate `VkViewport` struct, write x/y/w/h/min/max from params |
| **SF-06** | `CommandBuffer.set_scissor` | 843 | Same -- params discarded, NULL with count=1 | Must allocate `VkRect2D`, write offset+extent from params |

**Root cause:** These 6 functions treat Vulkan handle values as struct pointers. A `VkCommandPool` handle is an opaque 64-bit integer -- passing it as a struct pointer causes the driver to dereference an invalid address -> segfault.

### HIGH (logic errors) -- 3 bugs

| ID | Function | Line | Bug |
|----|----------|------|-----|
| **SF-07** | `Instance.enumerate_physical_devices` | 311 | Returns `count` (always 0) instead of `c32`. Also: inline extern declares count as `Int` but canon declares `Int32` |
| **SF-08** | `VulkanContext.init` | 1353 | Checks `phys_devices` (always 0) instead of `pdc`. Passes 0 as physical_device handle |
| **SF-09** | `Event.get_status` | 1131 | Compares to `3` instead of `VK_EVENT_SET` (1) |

### MEDIUM -- 3 bugs

| ID | Function | Line | Bug |
|----|----------|------|-----|
| **SF-10** | `Buffer.create` / `create_from_struct` | 451 | Size field never populated from create_info |
| **SF-11** | `DeviceMemory.allocate` | 1496 | Size field never populated |
| **SF-12** | `VulkanContext.destroy` | 1372 | Only checks instance != 0, device could be 0 |

### LOW -- 3 issues

| ID | Issue |
|----|-------|
| **SF-13** | `build_cstr_array` leaks individual C string allocations |
| **SF-14** | All destroy functions rely solely on `requires` contracts -- if handle is 0, contract violation, but no runtime guard |
| **SF-15** | Out-parameter convention: all create functions use `let x: Int = 0; vkCreate*(ci, 0, x)`. XIOM v0.48.0 passes the ADDRESS of `let` locals to extern `*T` params -- verified correct. Not a bug. |

---

## 2. AAA ENGINE READINESS SCORECARD

| # | Domain | Status | Missing |
|---|--------|--------|---------|
| 1 | Resource Lifetime | [OK] PRESENT | -- |
| 2 | Multithreaded Rendering | [WARN] PARTIAL | No thread-safe abstraction, single-queue convenience layer |
| 3 | Memory Management | [WARN] PARTIAL | No VMA-style sub-allocator, missing bind2/requirements2 |
| 4 | Pipeline Management | [WARN] PARTIAL | Pipeline cache serialization not in bridge |
| 5 | Descriptor Management | [OK] PRESENT | -- |
| 6 | Render Pass Management | [OK] PRESENT | -- |
| 7 | Shader Compilation | [FAIL] MISSING | No GLSL/HLSL->SPIR-V toolchain, no shader reflection |
| 8 | Texture Loading | [FAIL] MISSING | No image decoders, no automated mipmap pipeline |
| 9 | Synchronization | [OK] PRESENT | -- |
| 10 | Frame Pacing | [OK] PRESENT | -- |
| 11 | Ray Tracing | [OK] PRESENT | -- |
| 12 | GPU-Driven Rendering | [OK] PRESENT | -- |
| 13 | Debug Tools | [OK] PRESENT | -- |
| 14 | Profiling | [OK] PRESENT | -- |
| 15 | Platform Support | [OK] PRESENT | Windows, Linux, macOS, headless |

**Overall: 9/15 PRESENT, 4/15 PARTIAL, 2/15 MISSING**

---

## 3. Compiler Gaps (xiom v0.48.0)

| ID | Gap | Status |
|----|-----|--------|
| CG-01 | Float32/Float64 Vec element reads return garbage (sitofp bug) | [WARN] Reproduced |
| CG-02 | E001 "use of moved value" on Float64 in math.sin() calls | [WARN] Cosmetic, workaround exists |
| CG-03 | Cross-module `use xiom.*` catalog doesn't resolve from single file | [WARN] Multi-file merge works |
| CG-04 | `extern "C"` block at top-level without `module` declaration -> P001 parse error | [WARN] Fixed by adding module declaration |
| CG-05 | `xvk_app_should_close` returns 1 when app handle is valid but window is null (headless) | [WARN] Design limitation |

**No new compiler gaps found in this audit.** All issues are in the XIOM wrapper code (vulkan_safe.xi), not the compiler.
