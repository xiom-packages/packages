# AUDIT: xiom.cuda

## Status (2026-10-10)

System-library implementation at 0.2.0. The pre-pilot module (an 11 KB
static-extern surface expecting the CUDA Toolkit/import libraries) is
preserved in git history only; the 0.2.0 probe uses the **driver API**
library that ships with the NVIDIA driver.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.2 |
| Upstream | NVIDIA CUDA driver (proprietary; nothing vendored) |
| Link model | one `--c-source` TU (bridge); `nvcuda.dll` dlopen'd at runtime |
| FFI confinement | all `unsafe`/`extern` in the root module `cuda.xi` (G5) |
| Suite | `tests/test_conformance.xi`, 5 checks (live driver + memory round trip) |
| Runs | 5/5 x2 on the pin (driver 13040, RTX 3070 Ti, cc 806, memtest ok) |

## Design notes

- **Driver API only**: `nvcuda.dll` is a system component on any machine
  with an NVIDIA driver, so the package has no Toolkit dependency and no
  vendored bytes; `cuInit` + context creation work without one.
- **Packed/scalar returns (finding B-11 workaround)**: the probe returns
  `(driver_version << 8) | device_count` (negative = `-code`) and exposes
  the device name through a static C string -- no out-param slots for this
  driver-heavy call (the same slot-recycle risk that B-11 documents for the
  Vulkan driver).
- Classification: loader missing / no device -> SKIP (deterministically
  testable with a bogus module name); step failures -> FAIL with the failing
  step code in the message.
- The `_v2` entry-point names are the stable driver ABI; a symbol rename on
  a future driver surfaces as failure code 1 (ABI).

## Known limitations

- Pilot scope: driver version, device 0 identity/cc, and a 64 KiB memory
  round trip; multi-device, streams, VMM APIs are Phase 2.
- Device selection: device 0 (no preference logic).
- Windows x64 primary; the driver API also exists on Linux (`libcuda.so.1`)
  but no Linux run has been made.
