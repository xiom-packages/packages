# PROVENANCE: xiom.vma

Upstream-first doctrine: `docs/UPSTREAM-FIRST.md` (xiom-packages/packages).
This file records what was studied, what was vendored, and what is derived
for the **full top-level `vma*` surface** work (SDK 100% program, slice B3).

## Upstream

| Item | Value |
|------|-------|
| Project | Vulkan Memory Allocator (VMA) -- https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator |
| License | MIT (`vendor/LICENSE-vma.txt`; per-file headers carry the AMD/MIT notice) |
| Clone | `E:\repos\VulkanMemoryAllocator` (shallow, owner-provided shared clone space; ledged in `E:\repos\CLEANUP.md`) |
| Oracle pin | tag **v3.3.0**, commit `1d8f600fd424278486eade7ed3e877c99f0846b1` -- the header shipped by Vulkan SDK 1.4.350.0 (`C:\VulkanSDK\1.4.350.0\Include\vma\vk_mem_alloc.h`, SHA256 `90CE12FC...B112`) is **byte-identical** to `include/vk_mem_alloc.h` at this tag (blob `8df03649b5b97acc1e43839d2857d32d267958ca`) |
| Vendor pin | tag **v3.4.0**, commit `3aa921224c154a0d2c43912bc88e1c42ce1f7607` -- base of the pre-existing `vendor/vk_mem_alloc.h` (SPEC section 2; single documented include rewrite, diff = 1 line) |

Both tags were fetched (depth 1) into the same shallow clone.

## Vendored files (byte-pinned; re-hash on touch)

Pre-existing (0.2.0 pin, unchanged by this slice):

- `vendor/vk_mem_alloc.h` -- upstream v3.4.0 with the one documented rewrite
  (`<vulkan/vulkan.h>` -> `"vulkan/vulkan.h"`; SPEC section 2).
- `vendor/vulkan/{vulkan.h, vulkan_core.h, vk_platform.h, vk_video/*}` --
  Vulkan-Headers `vulkan-sdk-1.4.350.0` (Apache-2.0; `vendor/LICENSE-vulkan.md`).

Added by this slice (config enablers for the two gated oracle functions):

- `vendor/vulkan/vulkan_win32.h` -- Vulkan-Headers v1.4.350
  (`E:\repos\Vulkan-Headers`, KhronosGroup/Vulkan-Headers). Git blob
  `5c7e8bd6d7e362cae5f67b023be19efcc3999a2c`; byte-identical to the SDK copy
  and to the clone tag. Same archive pin as the existing core headers.
- `vendor/volk/volk.h`, `vendor/volk/volk.c` -- Volk (upstream
  https://github.com/zeux/volk, MIT; the SDK copy carries
  `VOLK_HEADER_VERSION 350`). Git blobs `ce50ba716cb7101317609cf30f8861d58610f5ff`
  and `4563bfe7f2120fac8ae717cbed900c858955178f`. The **only** modifications
  are three include rewrites in `volk.h` (`<vulkan/vk_platform.h>`,
  `<vulkan/vulkan_core.h>`, `<vulkan/vulkan_win32.h>` -> relative
  `../vulkan/...` paths; the package link line has no `-I` passthrough, the
  same policy as the `vk_mem_alloc.h` rewrite). `volk.c` is unmodified
  (`#include "volk.h"` resolves beside it).

## Derived vs independent

- **Derived (mechanical, from the oracle header)**: the C++ bridge wrappers,
  the XIOM extern surface and the family pass-through wrappers are emitted by
  `tools/gen_vma_full.py` from the declarations in the oracle header
  (signature mirroring + null-guard policy + export table). No upstream
  implementation code was copied into these files; the VMA implementation
  itself is the vendored header compiled by the bridge.
- **Independent**: the bridge support code (device setup, RHI slot registry,
  scalar getters, error probe) and `tests/test_full_surface.xi` are written for
  this package (not derived from upstream sources or tests).
- **Test vectors / golden data**: none imported from upstream; the functional
  probes are live-device checks (allocator/buffer/info round trip, null-argument
  guards, SKIP classification), not upstream golden files.
- The double-include "composition" pattern (`vma_full_bridge.cpp` includes the
  unchanged `src/vma_bridge.cpp`) exists so the VMA implementation compiles
  exactly once in the package with the extra config macros enabled.

## Re-carve procedure

1. Re-pin: update the oracle header path/version (SDK) and the VMA tag; verify
   the SDK header blob against the new tag (byte-identical) or record the delta.
2. Re-run `python tools/gen_vma_full.py` against the new oracle header; the
   generator fails closed if the family map misses a new function (add the
   family assignment, regenerate).
3. Re-apply the vendor procedure from `SPEC.md` section 2 (download, hash,
   rewrite the include line, update the per-file table) and re-hash the volk
   and `vulkan_win32.h` files (re-copy from the pinned Vulkan-Headers tag / SDK).
4. Re-run both suites x2 (`scripts/port.ps1 -Package xiom.vma` and
   `-Suite tests/test_full_surface.xi`), update `SPEC.md`, `README.md`,
   `AUDIT.md`, `docs/COVERAGE.md`, and record in `STATUS.json`.
