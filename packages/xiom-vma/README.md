# xiom.vma

Vulkan Memory Allocator v3.4.0 bindings for XIOM. VMA is **header-only**:
the vendored header plus the pinned Vulkan-Headers core compile into the
test binary with `--c-source`; the Vulkan loader (`vulkan-1.dll`) is loaded
at runtime. No SDK, no import library.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.4; 5/5 x2, live RTX 3070 Ti probe). 0.2.0 published in `eco-v0.1.124`;
> **0.3.0 published in `eco-v0.1.161`** (sha256 `a1cc09e2...`). **Lane:** bindings
> (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.vma;

fn main() {
  let p = vma_probe();
  if p.is_ok {
    io.println("VMA live: heaps=" + "see VmaInfo");
    // p.value.heap_count / .alloc_size / .verify
  } else if p.error.kind == VMA_LOAD_ABSENT || p.error.kind == VMA_NO_DEVICE {
    io.println("SKIP: " + p.error.message);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Probe | `vma_probe` -> `VmaInfo` (heap_count/alloc_size/verify), `vma_probe_named(dll)` |
| Kinds | `VMA_LOAD_ABSENT`, `VMA_NO_DEVICE` (SKIP), `VMA_PROBE_FAILED` (FAIL) |

The probe creates a Vulkan instance/device, initializes VMA, allocates a
64 KiB host-visible buffer, writes and verifies a mapped pattern, and tears
everything down. Details: `SPEC.md`; pins + the one-line vendored rewrite:
`SPEC.md` §2. Note: the result crosses as a packed int (finding B-11
workaround -- see `docs/BINDINGS-COMPILER-FINDINGS.md`).

## Tests

```
scripts/port.ps1 -Package xiom.vma
```

Expected: 5 `[PASS]`, exit 0 (or 2 with SKIP lines on a host without a
Vulkan device).

## Full top-level surface (0.3.0)

The package now binds **100% of the top-level `vma*` API** (72 functions) of
the Vulkan SDK 1.4.350.0 header (VMA v3.3.0): generated bridge wrappers +
typed XIOM family modules (`src/vma_full_*.xi`), all `VMA_NOT_NULL` pointer
arguments null-guarded. Counts and the non-FFI remainder: `docs/COVERAGE.md`;
upstream pin: `PROVENANCE.md`.

```xiom
use xiom.io;
use xiom.vma.full_rhi;   // typed RHI-path helpers (device -> allocator -> buffer)
use xiom.vma.full_ffi;   // raw bound surface + VkResult subset constants

fn main() {
  let slot = rhi_setup();               // >0 live, <= RHI_SKIP_LOADER -> SKIP
  if slot > 0 {
    let res = rhi_allocator_create(slot);   // vmaCreateAllocator via the wrapper
    if res == VK_SUCCESS { io.println("vmaCreateAllocator: ok"); }
    rhi_allocator_destroy(slot);
    rhi_teardown(slot);
  }
}
```

Full-surface suite (prints `bound=72/72`; live device or classified SKIP):

```
scripts/port.ps1 -Package xiom.vma -Suite tests/test_full_surface.xi -TimeoutSec 900
```

Expected: `bound=72/72` + 21 `[PASS]`, exit 0 (device-dependent checks print
SKIP on a host without a Vulkan device).
