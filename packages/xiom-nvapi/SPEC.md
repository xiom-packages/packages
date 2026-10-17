# SPEC: xiom.nvapi 0.1.0

NVIDIA NVAPI presence/identity/telemetry bindings, loader-only.
**Nothing is vendored**; `nvapi64.dll` is a system component of the NVIDIA
display driver. NVAPI exports only `nvapi_QueryInterface`; every declared
entry point is fetched by its numeric function id. This document is the exact
declared surface for 0.1.0.

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.nvapi` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Target | NVIDIA NVAPI `nvapi64.dll` (display-driver component) |
| Upstream | NVIDIA NVAPI SDK (MIT-licensed public headers; the implementation is the installed driver) |
| Declaration oracle | `NVIDIA/nvapi` `nvapi.h` + `nvapi_interface.h` + `nvapi_lite_common.h` at pin |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 |
| Compiler pin | v0.64.6 |

## 2. G2 pin: soname + query interface + function ids + sample

**Soname:** `nvapi64.dll` (System32 system component).

**Export:** `nvapi_QueryInterface` (the only entry point used; all others are
resolved by id).

**Function ids (11):**

| Function | Id |
|----------|----|
| `NvAPI_Initialize` | `0x0150E828` |
| `NvAPI_Unload` | `0xD22BDD7E` |
| `NvAPI_GetErrorMessage` | `0x6C2D048C` |
| `NvAPI_GetInterfaceVersionString` | `0x01053FA5` |
| `NvAPI_SYS_GetDriverAndBranchVersion` | `0x2926AAAD` |
| `NvAPI_EnumPhysicalGPUs` | `0xE5AC921F` |
| `NvAPI_GPU_GetFullName` | `0xCEEE8E9F` |
| `NvAPI_GPU_GetPCIIdentifiers` | `0x2DDFB66E` |
| `NvAPI_GPU_GetBusId` | `0x1BE0B8E5` |
| `NvAPI_GPU_GetThermalSettings` | `0xE3640A56` |
| `NvAPI_GPU_GetDynamicPstatesInfoEx` | `0x60DED2ED` |

**ABI facts:** `NvPhysicalGpuHandle` is an opaque pointer (kept in C);
`NvAPI_ShortString` is 64 bytes; `NVAPI_MAX_PHYSICAL_GPUS` 64;
`NVAPI_MAX_THERMAL_SENSORS_PER_GPU` 3; `NVAPI_MAX_GPU_UTILIZATIONS` 8;
`NVAPI_THERMAL_TARGET_ALL` 15; `NVAPI_THERMAL_TARGET_GPU` 1;
`MAKE_NVAPI_VERSION(type, ver) = sizeof(type) | (ver << 16)`.

**Struct layout (asserted at compile time):**

| Struct | Size | Version word | Key offsets |
|--------|------|--------------|-------------|
| `NV_GPU_THERMAL_SETTINGS_V2` | 68 | `0x20044` | `count` 4, `sensor` 8, sensor stride 20 |
| `NV_GPU_DYNAMIC_PSTATES_INFO_EX` | 72 | `0x10048` | `utilization` 8, domain stride 8, `percentage` +4 |

**Status values used:** `NVAPI_OK = 0`; SKIP-class `NVAPI_LIBRARY_NOT_FOUND
= -2`, `NVAPI_NO_IMPLEMENTATION = -3`, `NVAPI_NVIDIA_DEVICE_NOT_FOUND = -6`,
`NVAPI_DRIVER_NOTRUNNING = -156`; optional-metric `NVAPI_NOT_SUPPORTED =
-104`.

**Local sample (NOT the pin; nothing committed):** System32
`nvapi64.dll`, 574,040 B, file version 32.0.16.1692 (NVAPI 616.92), SHA256
`11F66428948436B666DFC987A8D3DF4A0CA6293D10E4F9DDF7E40A10D759EF73`.
Recorded runtime: interface `NVidia Complete Version 1.10`; driver raw
**61692** -> **616.92**, branch `r616_69`; 1 physical GPU,
`NVIDIA GeForce RTX 3070 Ti`; PCI vendor 0x10DE (4318), device 0x2482
(9346), revision 161, combined word 612503774, subsystem 1083053144, bus id
8; 49 C; GPU utilization 3%.

### Driver-version encoding

`NvAPI_SYS_GetDriverAndBranchVersion` returns **major\*100 + minor**
(61692 = 616.92), not a bitfield. The bridge stores the raw word and
exposes decoded `driver_version_major/minor`; the suite asserts
`raw == major*100 + minor`.

### PCI identifier encoding

The 32-bit `pciDeviceId` is `(device_id << 16) | vendor_id`. The bridge
exposes the raw combined word as `device_id` plus decoded `vendor_id`
(0x10DE) and `pci_device_id` (0x2482 here).

### Re-pin procedure

1. Refresh the `NVIDIA/nvapi` clone; re-verify the ids in
   `nvapi_interface.h` and the struct versions in `nvapi.h`.
2. Update the oracle hashes and pin in `PROVENANCE.md`; update the layout
   asserts in `nvapi_bridge.c` in the same commit.
3. Re-run `scripts/port.ps1 -Package xiom.nvapi` x2 and record
   `STATUS.json`.

## 3. Declared surface (100% of 0.1.0)

### 3.1 Public functions

| Function | Contract |
|----------|----------|
| `nvapi_probe() -> Result[NvapiInfo, NvapiError]` | Load `nvapi64.dll`, resolve the id set, initialize, read interface/driver versions, enumerate physical GPUs, query GPU 0, unload. |
| `nvapi_probe_named(dll: Str)` | Same against a named module (deterministic SKIP path). |
| `nvapi_is_skip(&NvapiError) -> Bool` | SKIP classifier: `LOAD_ABSENT`, `DRIVER_ABSENT`, `NO_DEVICE`. |
| `nvapi_summary(&NvapiInfo) -> Str` | One-line human-readable summary. |

### 3.2 Snapshot fields (16)

| Area | Fields | Coverage |
|------|--------|----------|
| Interface | interface_version | 1/1 |
| Driver | driver_version_raw, major, minor, branch | 4/4 |
| Enumeration | gpu_count | 1/1 |
| GPU identity | gpu_name, device_id, vendor_id, pci_device_id, subsystem_id, revision_id, ext_device_id, bus_id | 8/8 |
| Optional telemetry | temperature_c, utilization_gpu_pct | 2/2 |

Only GPU 0 is queried; `gpu_count` reports the full physical enumeration.
Additional per-GPU queries are Phase 2.

## 4. Optional-metric policy

`temperature_c` and `utilization_gpu_pct` are `-1` when
`NvAPI_GPU_GetThermalSettings` / `NvAPI_GPU_GetDynamicPstatesInfoEx` returns
`NVAPI_NOT_SUPPORTED`. Every other status fails the probe with
`NVAPI_API_FAILED` and the raw status in `code`. This lets presence checks
work on TCC/headless hosts where sensors are absent.

## 5. Typed errors

`NvapiError { kind, stage, code, message }`:

| Kind | Class | Meaning |
|------|-------|---------|
| `NVAPI_LOAD_ABSENT` (0) | SKIP | `nvapi64.dll` missing |
| `NVAPI_DRIVER_ABSENT` (1) | SKIP | initialize reports no driver/library/implementation |
| `NVAPI_NO_DEVICE` (2) | SKIP | no physical GPU |
| `NVAPI_ABI` (3) | FAIL | `nvapi_QueryInterface` or a required id missing |
| `NVAPI_API_FAILED` (4) | FAIL | a declared query failed (raw status in `code`) |
| `NVAPI_INTERNAL` (5) | FAIL | bridge/internal failure |

`stage` names the operation (load, query-interface, initialize,
interface-version, driver-version, enumerate, name, pci-identifiers, bus-id,
thermal, utilization, unload).

## 6. Live evidence (v0.64.6, RTX 3070 Ti, driver 616.92)

`scripts/port.ps1 -Package xiom.nvapi -TimeoutSec 180` x2 -> **25/25 pass**.

- Presence: interface `NVidia Complete Version 1.10`; driver raw 61692 ->
  616.92, branch `r616_69`.
- Enumeration: 1 physical GPU.
- Identity: `NVIDIA GeForce RTX 3070 Ti`; vendor 0x10DE, device 0x2482,
  revision 161, bus id 8; combined word decomposes exactly.
- Optional telemetry: 49 C, GPU utilization 3%.
- Stability: repeated probes agree on name and driver version.

## 7. Deliberately not declared in 0.1.0

- Display/EDID/output topology, display driver settings, D3D/GL interop and
  device creation.
- Clock, power, fan, voltage, P-state and thermal **control** (read-only
  utilization/temperature only).
- I2C, SLI, stereo, surround, GSync, HDR and driver-profile APIs.
- Multiple GPUs beyond GPU 0, logical-GPU/display handles, TCC-specific
  enumeration.
- `NvAPI_GetDisplayDriverVersion` (deprecated) and the older bitfield
  version helpers.

## 8. Test contract

Suite: `tests/test_conformance.xi` -- 23 checks: SKIP classifier (5),
deterministic SKIP path (1), live presence/driver (5), enumeration (1),
identity (8), optional telemetry (2), summary (1), stability (2). CI without
an NVIDIA GPU stays green via SKIP classification.
Command (cwd = this package directory; the runner hook adds the C source):

```
scripts/port.ps1 -Package xiom.nvapi -TimeoutSec 180
```

## 9. Design boundary (G5)

`nvapi.xi` is the only module with `unsafe`/`extern "C"`; it calls the
integer-only bridge `nvapi_bridge.c`, which loads `nvapi64.dll`, resolves
`nvapi_QueryInterface`, fetches the declared function pointers by id, keeps
all GPU handles in C, and caches the snapshot in static buffers. No foreign
pointer or handle crosses the FFI.
