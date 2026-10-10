# SPEC: xiom.cuda -- CUDA driver-API bindings (runtime loader, nothing vendored)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.cuda` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Target | NVIDIA CUDA **driver API** (`nvcuda.dll`) -- the system component that ships with any NVIDIA driver (no CUDA Toolkit required) |
| Upstream | NVIDIA CUDA driver (proprietary; **nothing vendored**) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 |
| Compiler pin | v0.64.2 |

## 2. G2 pin: soname + entry points + constants + sample

**Soname:** `nvcuda.dll` (System32 system component).

**Entry points (11):** `cuInit`, `cuDriverGetVersion`, `cuDeviceGetCount`,
`cuDeviceGetName`, `cuDeviceGetAttribute`, `cuCtxCreate_v2`,
`cuCtxDestroy_v2`, `cuMemAlloc_v2`, `cuMemFree_v2`, `cuMemcpyHtoD_v2`,
`cuMemcpyDtoH_v2`. The `_v2` suffixes are the stable driver-ABI names (the
plain names also exist on current drivers).

**Constants:** `CUDA_SUCCESS = 0`; `CUDA_ERROR_NO_DEVICE = 100`;
`CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR = 75` / `_MINOR = 76`.

**Local sample (NOT the pin; nothing committed):** System32 `nvcuda.dll`,
4,790,504 B, file version 32.0.16.1692, SHA256
`F2B550E83F56B7B819EFE382D712D125EE180341F012BD0ABA2288320609A45A`.
Recorded runtime: driver API **13040** (13.4), 1 device,
`NVIDIA GeForce RTX 3070 Ti`, compute capability 806 (8.6).

### Re-pin procedure

1. Re-verify the entry-point names against a newer driver (the `_v2`
   suffixes are the stable ABI; a probe run reports mismatches as code 1).
2. Update the sample row and the recorded runtime values in this SPEC and
   `README.md`/`AUDIT.md`.
3. Re-run `scripts/port.ps1 -Package xiom.cuda` x2 and record
   `STATUS.json`.

## 3. Design and safe boundary (G5)

`cuda.xi` is the only module with `unsafe`/`extern "C"`; it calls the
integer-only bridge (`src/cuda_bridge.c`), which loads `nvcuda.dll` at
runtime and runs one full probe, caching the results:

- `cuInit(0)` -> driver version -> device count -> device 0 name ->
  compute capability (attributes 75/76) -> **fresh context ->
  `cuMemAlloc` 64 KiB -> HtoD -> DtoH -> pattern compare** -> free ->
  context destroy.
- `cuprobe_run` returns the packed success value
  `(driver_version << 8) | device_count`; negative values are `-code`
  (100 loader missing / 101 no device -> SKIP; 1..9 step failures -> FAIL).
  Scalar/packed returns avoid out-param slots (finding B-11 applies to
  driver-heavy calls); `cuprobe_device_name` exposes a static C string read
  with `Str::from_c_str`.
- `cuda_probe_named` with a bogus module name exercises the SKIP path
  deterministically on every host.

## 4. Test contract

Suite: `tests/test_conformance.xi` -- 5 checks: SKIP classification (bogus
module), live probe (or SKIP without an NVIDIA GPU), version/devices sane,
device name reported, host->device->host round trip verified.

Command (cwd = this package directory; the runner hook adds the C source):

```
scripts/port.ps1 -Package xiom.cuda
```

Watchdog: allow >=180 s (one small C TU; ~5 s on the development machine).

## 5. Scope

Pilot: driver version, device identity, compute capability, and a real
device-memory round trip. Phase 2 (`ROADMAP.md`): multi-device enumeration,
primary-context/stream wrappers, VMM API, and *separate decisions* for the
Toolkit libraries (cuBLAS/cuDNN/cuFFT/cuRAND -- not vendored either). The
pre-pilot static-extern surface is preserved in git history.
