# xiom.vma

Vulkan Memory Allocator v3.4.0 bindings for XIOM. VMA is **header-only**:
the vendored header plus the pinned Vulkan-Headers core compile into the
test binary with `--c-source`; the Vulkan loader (`vulkan-1.dll`) is loaded
at runtime. No SDK, no import library.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.2; 5/5 x2, live RTX 3070 Ti probe). **Lane:** bindings
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
