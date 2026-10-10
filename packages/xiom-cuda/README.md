# xiom.cuda

NVIDIA CUDA **driver API** bindings for XIOM. `nvcuda.dll` (present with any
NVIDIA driver -- no CUDA Toolkit needed) is loaded at runtime; **nothing is
vendored**.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.2; 5/5 x2, live RTX 3070 Ti: driver 13.4, cc 8.6, device-memory
> round trip). Published in `eco-v0.1.126` (sha256 `325aa2cb...`).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.cuda;

fn main() {
  let p = cuda_probe();
  if p.is_ok {
    io.println("CUDA driver " + "see CudaInfo");   // driver_version etc.
  } else if p.error.kind == CU_LOAD_ABSENT || p.error.kind == CU_NO_DEVICE {
    io.println("SKIP: " + p.error.message);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Probe | `cuda_probe` -> `CudaInfo` (driver_version/device_count/device_name/compute_capability/memtest_ok), `cuda_probe_named(dll)` |
| Kinds | `CU_LOAD_ABSENT`, `CU_NO_DEVICE` (SKIP), `CU_PROBE_FAILED` (FAIL) |

The probe covers `cuInit`, driver version, device 0 identity, compute
capability, and a real host -> device -> host pattern round trip on a fresh
context. Details and the ABI pin: `SPEC.md`. Toolkit libraries
(cuBLAS/cuDNN/...) are Phase 2, separate decisions.

## Tests

```
scripts/port.ps1 -Package xiom.cuda
```

Expected: 5 `[PASS]`, exit 0 (or 2 with a SKIP line on a host without an
NVIDIA GPU).
