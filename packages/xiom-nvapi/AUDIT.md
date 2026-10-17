# AUDIT: xiom.nvapi

## Status (2026-10-17, v0.64.6)

Loader-only implementation at 0.1.0: NVAPI presence + identity + a small
documented telemetry subset, typed errors, deterministic SKIP paths. The
package contains no NVIDIA code, no import library and no generated headers;
`nvapi_bridge.c` is original XIOM-side code with compile-time layout
assertions.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.6 |
| Decision | **system-library path only** (`nvapi64.dll`; nothing vendored) |
| Oracle | NVIDIA/nvapi `70d337db` (MIT); ids/versions/layouts + local DLL sample in `PROVENANCE.md` |
| Link model | none at build time; `LoadLibraryA` + `nvapi_QueryInterface` at run time |
| FFI confinement | all `unsafe`/`extern` in `nvapi.xi` (G5); the C bridge is support code that never links NVIDIA code |
| Suite | `tests/test_conformance.xi` |
| Runs (0.1.0) | RTX 3070 Ti / driver 616.92: **25/25 x2** |
| Handles | opaque `NvPhysicalGpuHandle`s never cross the FFI; only integers/strings do |

## Design notes

- **NVAPI is not a normal export surface.** Only `nvapi_QueryInterface` is
  exported; every function is fetched by a numeric id. A missing id is a
  hard `NVAPI_ABI` failure, not a silent partial probe.
- **Two-stage presence classification.** A missing DLL is
  `NVAPI_LOAD_ABSENT`; initialize returning `NVAPI_LIBRARY_NOT_FOUND`,
  `NVAPI_NO_IMPLEMENTATION`, `NVAPI_NVIDIA_DEVICE_NOT_FOUND` or
  `NVAPI_DRIVER_NOTRUNNING` is `NVAPI_DRIVER_ABSENT`; an empty physical-GPU
  enum is `NVAPI_NO_DEVICE`. All are SKIP.
- **Version semantics.** `NvAPI_SYS_GetDriverAndBranchVersion` returns
  `major*100 + minor` (61692 = 616.92). The first implementation decoded it
  as a bitfield and produced 0.3; the suite now asserts
  `raw == major*100 + minor` explicitly.
- **PCI identifier semantics.** `pciDeviceId` is a combined
  `(device << 16) | vendor` word. The bridge exposes the raw word plus
  decoded `vendor_id` (0x10DE) and `pci_device_id` (0x2482).
- **Optional telemetry.** Thermal and dynamic-P-state queries degrade to
  `-1` on `NVAPI_NOT_SUPPORTED`, so a TCC/headless presence check still
  succeeds; other statuses fail with the raw code.
- **Thermal target selection.** `NvAPI_GPU_GetThermalSettings` is called
  with `NVAPI_THERMAL_TARGET_ALL` (15); the bridge picks the sensor whose
  target is `NVAPI_THERMAL_TARGET_GPU` (1), avoiding a hard-coded sensor
  index.
- **Utilization domain.** The public header documents the domain order
  (GPU=0, FB=1, VID=2, BUS=3) but the current public header set no longer
  defines the `NVAPI_GPU_UTILIZATION_DOMAIN_GPU` symbol; the bridge uses
  index 0 and asserts the struct layout. This is recorded for the re-carve.
- **Best-effort unload.** `NvAPI_Unload` is called after the snapshot; its
  status is not allowed to mask a successful probe (the driver may be shared
  with other components).
- **v0.64.6 discipline compliance:** all foreign memory is touched only in
  C (B-20); no foreign pointers cross the FFI (B-23/B-25); flat records, no
  `Result[Option[T]]` (B-26); bridge locals prefixed `n_` (B-10); no
  allocation in confined blocks (B-05); raw-pointer results are converted
  inside the `unsafe` block (T006).

## Known limitations

- Windows only (NVAPI is a Windows API; no Linux soname exists).
- Only GPU 0 is queried; `gpu_count` reports the full enumeration.
- Read-only: no clock/power/fan/P-state control, display settings, EDID,
  I2C, SLI/stereo/surround or D3D/GL interop.
- `NVAPI_GPU_GetDynamicPstatesInfoEx` returns a 1-second utilization
  percentage; the field may legitimately be `-1` if the domain is absent.
- No display-handle APIs, so display topology/EDID is out of the declared
  subset.
