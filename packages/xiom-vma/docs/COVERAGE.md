# COVERAGE: xiom.vma -- top-level `vma*` API (SDK 100% program, slice B3)

Status: **bound = 72/72** (oracle == bridge exports == linked wrappers); suite
green x2 on the pinned compiler v0.64.3 (2026-10-11). This file records the
oracle inventory, the bound surface, the runtime resolution proof, and the
documented non-FFI remainder.

## 1. Oracle (measured, not hand-written)

| Field | Value |
|-------|-------|
| Header | `C:\VulkanSDK\1.4.350.0\Include\vma\vk_mem_alloc.h` |
| SHA256 | `90CE12FC4A2466235A09AE02905DD0C13AEE80C1BBF11B331AB61230C2CEB112` |
| Upstream identity | GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator tag **v3.3.0**, commit `1d8f600fd424278486eade7ed3e877c99f0846b1`; the SDK header is **byte-identical** to the upstream file (git blob `8df03649b5b97acc1e43839d2857d32d267958ca`) |
| Functions | **72** top-level `vma*` declarations (`VMA_CALL_PRE ... VMA_CALL_POST <name>(...)`) |
| Parser | `tools/gen_vma_full.py` (committed generator; no manual list) |

Two oracle declarations are config-gated in the header itself and are both
**enabled** in the generated bridge, so the oracle count is the bound count:

- `vmaImportVulkanFunctionsFromVolk` -- declared under `#ifdef VOLK_HEADER_VERSION`
  (Volk builds). The bridge compiles `vendor/volk` (`VOLK_IMPLEMENTATION`), which
  defines `VOLK_HEADER_VERSION`.
- `vmaGetMemoryWin32Handle` -- declared under `#if VMA_EXTERNAL_MEMORY_WIN32`
  (`VK_KHR_external_memory_win32`). The bridge defines `VK_USE_PLATFORM_WIN32_KHR`
  and vendors `vendor/vulkan/vulkan_win32.h`, so the macro is 1.

## 2. Bound surface

The bridge TU (`src/vma_full_bridge.cpp`, generated) composes the existing probe
bridge (`src/vma_bridge.cpp`, unchanged -- VMA implementation + packed probe)
and adds **one wrapper per oracle function** (`vmafull_wrap_<name>`), mirroring
the C signature. `VMA_NOT_NULL` pointer parameters are null-guarded: a null
argument returns `VK_ERROR_INITIALIZATION_FAILED` (or `VK_FALSE` / no-op for
`VkBool32` / `void` wrappers) instead of tripping `VMA_ASSERT`.

The XIOM side (`src/vma_full_ffi.xi` + one module per family) declares the bound
surface 1:1 and adds typed pass-through wrappers. Type mapping: pointers /
opaque handles / `size_t` / `HANDLE` -> `Int` (0 = null);
`uint32_t`/`VkBool32`/flags -> `Int32`; `VkDeviceSize`/`VkBuffer`/`VkImage`/
`VmaVirtualAllocation` -> `Int64`; `void` -> `Unit`.

| Family | Module | Functions |
|--------|--------|-----------|
| allocator | `src/vma_full_allocator.xi` | `vmaImportVulkanFunctionsFromVolk`, `vmaCreateAllocator`, `vmaDestroyAllocator`, `vmaGetAllocatorInfo`, `vmaGetPhysicalDeviceProperties`, `vmaGetMemoryProperties`, `vmaGetMemoryTypeProperties`, `vmaSetCurrentFrameIndex` |
| stats | `src/vma_full_stats.xi` | `vmaCalculateStatistics`, `vmaGetHeapBudgets`, `vmaBuildStatsString`, `vmaFreeStatsString` |
| memtype | `src/vma_full_memtype.xi` | `vmaFindMemoryTypeIndex`, `vmaFindMemoryTypeIndexForBufferInfo`, `vmaFindMemoryTypeIndexForImageInfo` |
| pool | `src/vma_full_pool.xi` | `vmaCreatePool`, `vmaDestroyPool`, `vmaGetPoolStatistics`, `vmaCalculatePoolStatistics`, `vmaCheckPoolCorruption`, `vmaGetPoolName`, `vmaSetPoolName` |
| allocation | `src/vma_full_allocation.xi` | `vmaAllocateMemory`, `vmaAllocateMemoryPages`, `vmaAllocateMemoryForBuffer`, `vmaAllocateMemoryForImage`, `vmaFreeMemory`, `vmaFreeMemoryPages`, `vmaGetAllocationInfo`, `vmaGetAllocationInfo2`, `vmaSetAllocationUserData`, `vmaSetAllocationName`, `vmaGetAllocationMemoryProperties`, `vmaGetMemoryWin32Handle`, `vmaMapMemory`, `vmaUnmapMemory`, `vmaFlushAllocation`, `vmaInvalidateAllocation`, `vmaFlushAllocations`, `vmaInvalidateAllocations`, `vmaCopyMemoryToAllocation`, `vmaCopyAllocationToMemory` |
| defrag | `src/vma_full_defrag.xi` | `vmaCheckCorruption`, `vmaBeginDefragmentation`, `vmaEndDefragmentation`, `vmaBeginDefragmentationPass`, `vmaEndDefragmentationPass` |
| binding | `src/vma_full_binding.xi` | `vmaBindBufferMemory`, `vmaBindBufferMemory2`, `vmaBindImageMemory`, `vmaBindImageMemory2` |
| buffer | `src/vma_full_buffer.xi` | `vmaCreateBuffer`, `vmaCreateBufferWithAlignment`, `vmaCreateAliasingBuffer`, `vmaCreateAliasingBuffer2`, `vmaDestroyBuffer` |
| image | `src/vma_full_image.xi` | `vmaCreateImage`, `vmaCreateAliasingImage`, `vmaCreateAliasingImage2`, `vmaDestroyImage` |
| virtual | `src/vma_full_virtual.xi` | `vmaCreateVirtualBlock`, `vmaDestroyVirtualBlock`, `vmaIsVirtualBlockEmpty`, `vmaGetVirtualAllocationInfo`, `vmaVirtualAllocate`, `vmaVirtualFree`, `vmaClearVirtualBlock`, `vmaSetVirtualAllocationUserData`, `vmaGetVirtualBlockStatistics`, `vmaCalculateVirtualBlockStatistics`, `vmaBuildVirtualBlockStatsString`, `vmaFreeVirtualBlockStatsString` |

Total: 8 + 4 + 3 + 7 + 20 + 5 + 4 + 5 + 4 + 12 = **72**.

In addition, the RHI-path support API (device -> allocator -> buffer -> info ->
teardown, `src/vma_full_rhi.xi` over bridge getters) is generated for the
functional suite; it is support code, not part of the counted oracle surface.

The bridge is built against the package's vendored header (VMA **v3.4.0**,
superset of the oracle; see `SPEC.md` section 2). VMA v3.4.0 adds four
functions that are *not* part of the SDK v3.3.0 oracle
(`vmaAllocateDedicatedMemory`, `vmaCreateDedicatedBuffer`,
`vmaCreateDedicatedImage`, `vmaGetMemoryWin32Handle2`); they are compiled into
the TU as part of the vendored implementation but intentionally expose no
wrappers -- the bound surface is defined by the oracle header only.

## 3. Runtime resolution proof

`tests/test_full_surface.xi` (run: `scripts/port.ps1 -Package xiom.vma -Suite
tests/test_full_surface.xi -TimeoutSec 900`) prints the line

```
bound=72/72
```

and checks, at runtime:

| Check | Evidence |
|-------|----------|
| bridge exports == oracle | `vmafull_export_count()` == `vmafull_oracle_count()` == 72 |
| runtime oracle == generated const | `VMA_FULL_ORACLE_COUNT == 72` (generated) |
| every wrapper linked | `vmafull_link_proof()` references all 72 wrappers; returns 72 |
| name spot checks | export[0] `vmaImportVulkanFunctionsFromVolk`, export[1] `vmaCreateAllocator`, export[last] `vmaFreeStatsString` |

Functional probes (live device, wrappers driven from XIOM):

- **RHI path**: `vmaCreateAllocator` -> `vmaCreateBuffer` (64 KiB
  host-visible) -> `vmaGetAllocationInfo` (size 65536, memoryType, device
  memory bound) -> `vmaGetMemoryWin32Handle` (config-gated function, real
  call: returns `VK_ERROR_FEATURE_NOT_PRESENT` because the win32 handle fn is
  not enabled at device creation -- the documented VMA outcome) ->
  `vmaDestroyBuffer` -> `vmaDestroyAllocator` -> device teardown.
- **Null-argument error path**: a 7-shape guard bitmask (including the two
  config-gated wrappers and a `VkBool32` wrapper) plus a direct XIOM-side call
  of the typed `vma_full_create_buffer` with all-null arguments ->
  `VK_ERROR_INITIALIZATION_FAILED`.
- **SKIP classification**: `rhi_setup` returns -100 (loader) / -101 (device)
  / -102 (queue); the suite reports SKIP (green) on hosts without a Vulkan
  device, never FAIL.

Runs (x2, dev machine with a live GPU):

```
tests/test_conformance.xi            5/5  x2   (existing suite, unchanged)
tests/test_full_surface.xi          21/21 x2   bound=72/72
```

## 4. Documented non-FFI surface (exclusions)

- **C++ class/template methods** of the implementation (`VmaAllocator_T`,
  `VmaAllocation_T`, `VmaPool_T`, `VmaVirtualBlock_T`,
  `VmaDefragmentationContext_T`, block/metadata classes, internal templates and
  algorithms): not part of the public C API and not FFI; the C surface above is
  the complete contract.
- **Data structures** (`VmaAllocatorCreateInfo`, `VmaAllocationInfo`, ...):
  C-side only. XIOM never reads through foreign pointers (B-11/B-20): results
  cross as scalar returns / C-side slot getters (`vmafull_info_*`).
- **Enums/macros as `pub const`**: not part of this slice (a constants module
  is possible future work); the test uses the small `VkResult` subset bound in
  `src/vma_full_ffi.xi`.
- **Vulkan side** (instance/device/queue creation): stays inside the bridge's
  device-setup support (the same path as the 0.2.0 probe); no `xiom.vulkan`
  dependency.
- **Volk loader initialization**: the volk globals are compiled in (so
  `vmaImportVulkanFunctionsFromVolk` links and is guard-probed), but the volk
  loader is not initialized; a real call would require `volkInitialize` +
  loading, which is outside the dynamic-loader design of this package.

## 5. Evidence pointers

- Generator: `tools/gen_vma_full.py` (oracle parse + emissions; run it to
  re-derive every generated artifact).
- Bridge: `src/vma_full_bridge.cpp` (generated; includes `src/vma_bridge.cpp`).
- XIOM surface: `src/vma_full_ffi.xi`, `src/vma_full_<family>.xi`,
  `src/vma_full_rhi.xi` (generated).
- Suite: `tests/test_full_surface.xi`.
- Provenance/pins: `PROVENANCE.md`, `SPEC.md` section 2 (per-file SHA256).
