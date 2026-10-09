# AUDIT: xiom.vma

## Status (2026-10-09)

Vendored-header implementation at 0.2.0. The pre-pilot module (a 20 KB
static-extern surface) is preserved in git history only; the 0.2.0 probe
drives the real device through a runtime-loaded loader.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.2 |
| Upstream | VMA v3.4.0 (MIT) + Vulkan-Headers vulkan-sdk-1.4.350.0 (Apache-2.0) |
| Link model | one `--c-source` TU (bridge with `VMA_IMPLEMENTATION`); loader dlopen'd |
| FFI confinement | all `unsafe`/`extern` in the root module `vma.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 5 checks (live allocation + mapped verify) |
| Runs | 5/5 x2 on the pin (heaps=3, alloc 65536, verify=1) |

## Design notes

- **Packed result (finding B-11 workaround)**: the bridge returns
  `(heap << 20) | (verify << 28) | size` (negative = `-classification`)
  instead of writing out-param slots. Slot memory written by this
  Vulkan-heavy call was observed recycled before XIOM could read it under
  the v0.64.2 runtime; the slot-call variant stays in the bridge as the
  reproduction (`docs/repro/bindings-pilot/vulkan-slot-recycle/`).
- VMA runs with `VMA_STATIC_VULKAN_FUNCTIONS 0` /
  `VMA_DYNAMIC_VULKAN_FUNCTIONS 1`; the two bootstrap procs
  (`vkGetInstanceProcAddr`, `vkGetDeviceProcAddr`) come from
  `LoadLibraryA("vulkan-1.dll")`.
- The single vendored rewrite is the include line
  `#include <vulkan/vulkan.h>` -> `#include "vulkan/vulkan.h"` (no `-I`
  passthrough); every other vendored byte is upstream (per-file SHA256 in
  `SPEC.md` §2; `vulkan_core.h` matches the `xiom.vulkan` pin).
- Classification: loader/device/queue absence -> SKIP (deterministically
  testable with a bogus module name); step failures -> FAIL.

## Known limitations

- Pilot scope: allocator lifecycle + one host-visible allocation with a
  mapped pattern; sub-allocation/pool/defrag APIs are Phase 2.
- Device selection: the first physical device with a graphics queue (no
  discrete-GPU preference).
- Windows x64 primary; the vendored path is portable, no other platform run.
