# AUDIT: xiom.nvml

## Status (2026-10-17, v0.64.6)

Loader-only implementation at 0.1.0: NVML telemetry essentials, typed
errors, deterministic SKIP paths. The package contains no NVIDIA code, no
import library and no generated headers; `nvml_bridge.c` is original
XIOM-side code with compile-time layout assertions.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.6 |
| Decision | **system-library path only** (`nvml.dll`; nothing vendored) |
| Pin | go-nvml `1a1e86da` (NVML 13.4.92 oracle; Apache-2.0 repo, NVIDIA header notice); oracle hash + local DLL sample in `PROVENANCE.md` |
| Link model | none at build time; `LoadLibraryA` + `GetProcAddress` at run time |
| FFI confinement | all `unsafe`/`extern` in `nvml.xi` (G5); the C bridge is support code that never links NVIDIA code |
| Suite | `tests/test_conformance.xi` |
| Runs (0.1.0) | RTX 3070 Ti / driver 616.92: **40/40 x2** |
| Handles | `nvmlDevice_t` never crosses the FFI; only integers/strings do |

## Design notes

- **One snapshot per call.** `nvml_system`/`nvml_device` load the module,
  initialize NVML, query, and shut down; the bridge caches the snapshot in
  static buffers and the XIOM getters read it immediately. This keeps the
  safe boundary free of lifetimes and foreign handles.
- **Required vs optional queries.** Fifteen entry points are required (ABI
  pin); seven are optional and degrade to `-1` (`""` for serial) on
  `NVML_ERROR_NOT_SUPPORTED`/`NOT_FOUND`. On this card `serial` is the only
  unsupported metric; everything else is live.
- **PCI identity.** NVML's `nvmlPciInfo_t.pciDeviceId` is a combined
  device+vendor word. The bridge keeps `pci_ids_raw` and exposes decoded
  `pci_vendor_id` (0x10DE) and `pci_device_id` (0x2482 here), avoiding the
  usual "device id 612503774" trap.
- **Memory v1.** The declared call is `nvmlDeviceGetMemoryInfo`
  (`total/free/used`), the broadest-compatibility ABI. The v2 `reserved`
  field is Phase 2.
- **Index handling.** A device-less host is `NVML_NO_DEVICE` (SKIP); an
  out-of-range index on a host with devices is `NVML_BAD_INDEX` (FAIL), so a
  caller bug is not masked as a platform skip.
- **Error classification** follows the lane doctrine: loader/driver/device
  absence is SKIP; a present driver that rejects a declared query is FAIL
  with the raw NVML return code in `code`.
- **v0.64.6 discipline compliance:** all foreign memory is touched only in
  C (B-20); no foreign pointers cross the FFI (B-23/B-25); flat records, no
  `Result[Option[T]]` (B-26); bridge locals prefixed `n_` (B-10); no
  allocation in confined blocks (B-05); raw-pointer results are converted
  inside the `unsafe` block (T006).

## Known limitations

- Windows loader name only (`nvml.dll`); Linux soname is Phase 2.
- No process enumeration, MIG, ECC, NVLink, topology, vGPU, events or
  mutating controls (see `SPEC.md` section 7).
- `nvml_device` supports indices the caller enumerates via `nvml_system`;
  there is no multi-device iteration helper yet.
- Snapshot calls are not reentrant (single cached snapshot by design).
- The live suite asserts this host's identity shape (NVIDIA vendor id,
  memory > 0, telemetry ranges); other NVIDIA hosts still pass the range
  and sentinel checks.
