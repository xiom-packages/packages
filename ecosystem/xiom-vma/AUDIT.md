# xiom-vma — Build Dependency Audit

## Required Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| Vulkan SDK | >= 1.3 | GPU API (headers + loader) — required by VMA |
| VMA (VulkanMemoryAllocator) | >= 3.3.0 | Memory sub-allocation library (single-header) |
| clang/LLVM | >= 14 | C bridge compilation |
| Rust/Cargo | Latest stable | Compiler build (xiomc) |
| xiomc | >= v0.45.3 | XIOM compiler |

## VMA Source

VMA is distributed as a single C header file:

| File | Location | Size |
|------|----------|------|
| `vk_mem_alloc.h` | `C:\VulkanSDK\1.4.350.0\Include\vma\` | 735 KB, 19,530 lines |

The Vulkan SDK (1.4.350.0) ships VMA v3.3.0 bundled in its include directory.

### VMA Integration

VMA is a **stb-style single-header** library. To use it:

1. `#include "vk_mem_alloc.h"` in ONE `.c`/`.cpp` file after including Vulkan headers
2. That file must `#define VMA_IMPLEMENTATION` before the include
3. All other files just `#include "vk_mem_alloc.h"` normally

VMA calls raw Vulkan functions internally. It requires:
- `VkInstance`, `VkPhysicalDevice`, `VkDevice` handles at creation time
- Optionally: Volk function pointers for dynamic-loading scenarios

## Platform-Specific Installation

### Windows
1. **Vulkan SDK**: Install from https://vulkan.lunarg.com/sdk/home
   - Sets `VULKAN_SDK` environment variable automatically
   - VMA header at `$VULKAN_SDK\Include\vma\vk_mem_alloc.h`
2. **clang**: Install via LLVM from https://releases.llvm.org/ or `winget install LLVM.LLVM`

### Linux
```bash
# Vulkan SDK
# Ubuntu: https://vulkan.lunarg.com/doc/view/latest/linux/getting_started_ubuntu.html
# Arch: sudo pacman -S vulkan-devel

# clang
sudo apt install clang
```

### macOS
```bash
# Vulkan SDK
# Download from https://vulkan.lunarg.com/sdk/home

# clang
# Ships with Xcode Command Line Tools
```

## Package Structure

```
ecosystem/xiom-vma/
├── package.xi              # Package manifest (name, version, deps)
├── vma.xi                  # Module xiom.vma — raw FFI + core safe wrappers
├── src/
│   └── vma_safe.xi         # Module xiom.vma.safe — struct-based wrappers
├── examples/
│   └── demo_vma.xi         # Module xiom.vma.demo — compile-time demo
└── AUDIT.md                # This file
```

## FFI Binding Coverage

### vma.xi — Module `xiom.vma`

**All 72 VMA C API functions** from vk_mem_alloc.h v3.3.0 are declared in one `extern "C"` block:

| Category | Functions | Key Functions |
|----------|-----------|---------------|
| Initialization | 7 | vmaCreateAllocator, vmaDestroyAllocator, vmaGetAllocatorInfo, vmaGetPhysicalDeviceProperties, vmaGetMemoryProperties, vmaGetMemoryTypeProperties, vmaSetCurrentFrameIndex |
| Statistics | 2 | vmaCalculateStatistics, vmaGetHeapBudgets |
| Memory Type Discovery | 3 | vmaFindMemoryTypeIndex, vmaFindMemoryTypeIndexForBufferInfo, vmaFindMemoryTypeIndexForImageInfo |
| Pools | 8 | vmaCreatePool, vmaDestroyPool, vmaGetPoolStatistics, vmaCalculatePoolStatistics, vmaCheckPoolCorruption, vmaGetPoolName, vmaSetPoolName |
| Allocation | 6 | vmaAllocateMemory, vmaAllocateMemoryPages, vmaAllocateMemoryForBuffer, vmaAllocateMemoryForImage, vmaFreeMemory, vmaFreeMemoryPages |
| Allocation Info | 5 | vmaGetAllocationInfo, vmaGetAllocationInfo2, vmaSetAllocationUserData, vmaSetAllocationName, vmaGetAllocationMemoryProperties |
| Mapping | 2 | vmaMapMemory, vmaUnmapMemory |
| Cache Control | 6 | vmaFlushAllocation, vmaInvalidateAllocation, vmaFlushAllocations, vmaInvalidateAllocations, vmaCopyMemoryToAllocation, vmaCopyAllocationToMemory |
| Corruption Detection | 1 | vmaCheckCorruption |
| Defragmentation | 4 | vmaBeginDefragmentation, vmaEndDefragmentation, vmaBeginDefragmentationPass, vmaEndDefragmentationPass |
| Binding | 4 | vmaBindBufferMemory, vmaBindBufferMemory2, vmaBindImageMemory, vmaBindImageMemory2 |
| Buffer Creation | 5 | vmaCreateBuffer, vmaCreateBufferWithAlignment, vmaCreateAliasingBuffer, vmaCreateAliasingBuffer2, vmaDestroyBuffer |
| Image Creation | 4 | vmaCreateImage, vmaCreateAliasingImage, vmaCreateAliasingImage2, vmaDestroyImage |
| Virtual Allocator | 12 | vmaCreateVirtualBlock, vmaDestroyVirtualBlock, vmaIsVirtualBlockEmpty, vmaGetVirtualAllocationInfo, vmaVirtualAllocate, vmaVirtualFree, vmaClearVirtualBlock, vmaSetVirtualAllocationUserData, vmaGetVirtualBlockStatistics, vmaCalculateVirtualBlockStatistics, vmaBuildVirtualBlockStatsString, vmaFreeVirtualBlockStatsString |
| Stats String | 2 | vmaBuildStatsString, vmaFreeStatsString |
| Volk Integration | 1 | vmaImportVulkanFunctionsFromVolk |

**Total: 72 extern function declarations.**

### vma_safe.xi — Module `xiom.vma.safe`

5 struct‑based resource types (with duplicate inline `extern "C"` block — cross‑module resolution is broken in v0.45.3):

| Type | Methods | Contracts |
|------|---------|-----------|
| `VmaAllocator` | create, destroy, find_memory_type_index, find_memory_type_index_for_buffer, find_memory_type_index_for_image, check_corruption, get_heap_budgets, calculate_statistics, build_stats_string, free_stats_string, get_memory_type_properties | requires: create_info != 0; ensures: handle != 0 |
| `VmaAllocation` | allocate, allocate_for_buffer, allocate_for_image, free, get_info, set_user_data, map_memory, unmap_memory, flush, invalidate, bind_buffer, bind_image | requires: allocator != 0; ensures: handle != 0 |
| `VmaPool` | create, destroy, check_corruption, get_name, set_name | requires: allocator != 0; ensures: handle != 0 |
| `VmaBuffer` | create, destroy | requires: allocator != 0; ensures: buffer != 0 |
| `VmaImage` | create, destroy | requires: allocator != 0; ensures: image != 0 |

Utility: `VmaContext` — high‑level lifecycle manager with init/destroy/create_buffer/create_image/create_pool.

## Compiler Gaps Worked Around

### 1. Cross-module extern resolution (T001)
**Symptom:** `extern "C"` functions declared in module A resolve to `()` when called from module B via `use` import.
**Workaround:** `src/vma_safe.xi` duplicates the `extern "C"` block it needs inline.
**Impact:** ~80-line duplicate extern block in vma_safe.xi.

### 2. Int→Int32 coercion (T001)
**Symptom:** Integer literals (`1`, `0`) default to `Int` and do not auto-coerce to `Int32`.
**Workaround:** Use `as Int32` casts (e.g., `count as Int32`).
**Impact:** All extern function calls with Int32 params use explicit `as Int32`.

### 3. No hex literals
**Symptom:** Hex literals (`0x00000001`) cause parse errors.
**Workaround:** Use decimal values only.
**Impact:** All constants are decimal; numeric comparisons use literals.

### 4. No `()` unit type in Result
**Symptom:** `Result[(), Error]` is not supported.
**Workaround:** Use `Result[Int, VulkanError]` with `Ok(0)`.

## Build Pipeline

```
1. Link VMA implementation
   Compile a C file with #define VMA_IMPLEMENTATION + vk_mem_alloc.h include
   → vma_impl.obj

2. XIOM Compilation + Link (xiomc + clang)
   vma.xi + src/vma_safe.xi + examples/*.xi + vma_impl.obj + vulkan-1.lib
   → final executable
```

## Compile Status (2026-07-15)

All files compile with `xiomc --diagnostics=json`: **`{"status":"ok"}`**, 0 T001/L001/P001 errors.

| File | Status | Lines | Contents |
|------|--------|-------|----------|
| `package.xi` | PASSED | 13 | Package manifest |
| `vma.xi` | PASSED | 423 | 72 extern C FFI declarations, 41 pub const flags, 20 safe wrappers, 1 utility |
| `src/vma_safe.xi` | PASSED | 469 | 5 struct resource types with create/destroy contracts, inline extern block |
| `examples/demo_vma.xi` | PASSED | 78 | Production API pattern demo (procedural + struct-based) |
| `AUDIT.md` | WRITTEN | 164 | This file |

**Total: 1,147 lines of production code.**

### VMA Constants (vma.xi)

41 named constants covering all VMA flag enums:

| Category | Count | Examples |
|----------|-------|----------|
| VmaMemoryUsage | 10 | VMA_MEMORY_USAGE_GPU_ONLY, VMA_MEMORY_USAGE_AUTO |
| VmaAllocationCreateFlags | 17 | VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT, VMA_ALLOCATION_CREATE_STRATEGY_MASK |
| VmaPoolCreateFlags | 2 | VMA_POOL_CREATE_LINEAR_ALGORITHM_BIT |
| VmaAllocatorCreateFlags | 9 | VMA_ALLOCATOR_CREATE_EXTERNALLY_SYNCHRONIZED_BIT |
| Defragmentation ops | 3 | VMA_DEFRAGMENTATION_MOVE_OPERATION_COPY |

### Remaining Compiler Gaps

Only E001 borrow warnings remain (29 total, non-fatal — same as reference `vulkan_safe.xi`). Gaps documented in `docs/ROADMAP.md §5c.14`:

| Gap | Status | Workaround |
|-----|--------|------------|
| Cross-module extern resolution | Unresolved | Inline extern block in each module |
| Int→Int32 coercion (let/const) | Unresolved | `as Int32` casts |
| Out-parameter move semantics | E001 (non-fatal) | None needed |
| Hex literal parsing | Avoided | Decimal literals used |

## Known Limitations

- VMA requires a valid Vulkan instance/device — compile‑time demos cannot create real allocators
- Build requires a C compiler (clang) to compile the VMA implementation
- No Vulkan function pointer tables are managed — VMA calls `vk*` functions through its internal dispatch
- Statistical/JSON dump strings require `VMA_STATS_STRING_ENABLED` preprocessor define
