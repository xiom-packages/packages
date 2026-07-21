# xiom-vulkan — Production Roadmap

**Current rating: 7/10** — Solid C bridge, good XIOM layer. Incomplete safety coverage.
**C bridge**: 29 files, 368 functions, 0 errors, 0 warnings (clang -O2 -Wall -Wextra)
**XIOM layer**: 21 files — raw bindings (755 VK functions), safe wrappers (24+ types, contracts), legacy xvk_app API (100+ functions)
**12 demos**: All compile and run, including 3D orbital cubes and game-style GUI showcase
**Compiler**: xiomc v0.49.2 (798/798 tests)

---

## Honest Assessment

xiom-vulkan is the most mature ecosystem package. The C bridge has been hardened through 6 production sprints — 10+ vkBind checks, 6 vkMapMemory checks, offscreen leak fixes, QueueSubmit error handling, thread-local error buffer, camera per-app context, descriptor caching. The XIOM layer has three complete sub-modules: raw auto-generated bindings (vulkan_extern.xi, 755 functions), safe resource wrappers (vulkan_safe.xi, 24+ types with contracts), and a legacy convenience API (vulkan.xi/wrapper.xi, 100+ functions).

The remaining gaps are:
1. **Safety coverage**: vulkan.xi has contracts on ~60% of functions. vulkan_safe.xi covers ~40% of Vulkan entry points.
2. **Multi-instance**: Global camera/instance state still uses old static globals in some code paths.
3. **Struct marshalling**: 1306 lines in vulkan_structs.xi should move to xiom-ffi.
4. **Demo stability**: The imgui demo has DPI/fullscreen issues — compiler-related, not bridge-related.

---

## Phase 1: Safety Coverage (7 → 8/10)

### VK-01: Add `requires`/`ensures` contracts to ALL public functions in vulkan.xi
**CRITICAL** | `vulkan.xi`
Currently ~60% coverage. Remaining ~40% need contracts (handle validation, range checks, state guards).

### VK-02: Add `invariant` on `VulkanApp` struct
**CRITICAL** | `vulkan.xi`
The wrapped `Int` handle needs: `value != 0` when valid, and a validity flag. Currently no invariant — invalid handles crash at runtime.

### VK-03: Add frame lifecycle guard — prevent `end_frame` without `begin_frame`
**CRITICAL** | `vulkan.xi` / `wrapper.xi`
Track `in_frame: Bool` at wrapper level. `end_frame` requires `in_frame == true`.

### VK-04: Complete vulkan_safe.xi coverage for all commonly-used VK entry points
**HIGH** | `vulkan_safe.xi`
Currently ~40% of 755 VK functions have safe wrappers. Target: 80% of commonly-used subset (~150 functions).

### VK-05: Add `destroy` methods to all resource types in vulkan_safe.xi
**HIGH** | `vulkan_safe.xi`
All create functions need paired destroy. Currently ~90% coverage.

### VK-06: Add VkResult → XIOM error mapping for all safe functions
**MEDIUM** | `vulkan_safe.xi`
Standardize `Result[T, VulkanError]` pattern across all wrappers.

---

## Phase 2: C Bridge Hardening (8 → 9/10)

### VK-07: Remove remaining global state from C bridge
**CRITICAL** | Multiple C files
Camera state moved to XvkApp (done in Sprint 7). Remaining: instance/device/extension binding globals in `xvk_bind_extensions.c`, `xvk_bind_swapchain.c`, `xvk_bind_raytracing.c`. Need XvkContext struct.

### VK-08: Add memory allocator thread safety
**HIGH** | `xvk_memory_alloc.c`
`g_ma` is a static global. Add mutex or per-context allocator.

### VK-09: Fix recreate_swapchain framebuffer rebuild regression
**HIGH** | `xvk_swapchain.c`
Documented in BRIDGE_AUDIT.md: after window resize, framebuffers are not rebuilt → NULL pointer crash.

### VK-10: Add queue family validation at queue creation
**MEDIUM** | `xvk_app.c`
`vkGetDeviceQueue` result assigned without verifying queue family index is valid.

---

## Phase 3: Ecosystem Integration (9 → 10/10)

### VK-11: Migrate inline `extern "C"` malloc/free to `use xiom.ffi`
**HIGH** | `vulkan.xi`, `vulkan_safe.xi`
stdlib `xiom.ffi` already has `alloc()/free()` with contracts. Replace local inline declarations.

### VK-12: Move struct marshalling primitives to xiom-ffi
**MEDIUM** | `vulkan_structs.xi` → `xiom-ffi/src/marshal.xi`
1306 lines of byte-offset struct builders. This is generic FFI utility, not Vulkan-specific.

### VK-13: Add `use xiom_ffi.ptr` for SafePtr wrappers on buffer/image memory
**LOW** | `vulkan.xi`, `vulkan_safe.xi`
Replace raw `Int` memory handles with `SafePtr` wrappers from xiom-ffi.

### VK-14: Full test suite for all 100+ public vulkan.xi functions
**MEDIUM** | `tests/`
Currently only a CI smoke test and a windowed smoke test. Need property-based tests for contract violations.

### VK-15: Runtime performance benchmarks
**LOW** | Compare xvk_app overhead vs raw Vulkan.

---

## Compiler/Stdlib Blockers

| Gap | Impact | Status |
|-----|--------|--------|
| G-28 E001 extern out-param moved | All unsafe FFI calls trigger warnings (G-28, ~41 instances) | P2 non-fatal |
| G-03 pub const module limit | vulkan_constants_all.xi has 3691 constants, near compiler limit of ~99 file-level consts | P2 |
| CG-01b Int32→Float32 | Fixed v0.48.8. Workaround removed. | ✅ |
| `unknown type T` | Generic `Result[T, E]` in wrapper.xi triggers warning. Cosmetic. | Open |
| `unknown type Vec[UInt8]` | Vec element generic not resolving. Cosmetic. | Open |
