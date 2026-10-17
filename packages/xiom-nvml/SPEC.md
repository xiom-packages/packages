# SPEC: xiom.nvml 0.1.0

NVIDIA NVML (Management Library) telemetry bindings, loader-only.
**Nothing is vendored**; `nvml.dll` is a system component of the NVIDIA
display driver. This document is the exact declared surface for 0.1.0.

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.nvml` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Target | NVIDIA NVML `nvml.dll` (display-driver component, no CUDA Toolkit required) |
| Upstream | NVIDIA NVML (proprietary driver component; **nothing vendored**) |
| Declaration oracle | `NVIDIA/go-nvml` `gen/nvml/nvml.h` at pin (NVML 13.4.92) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 |
| Compiler pin | v0.64.6 |

## 2. G2 pin: soname + entry points + constants + sample

**Soname:** `nvml.dll` (System32 system component).

**Entry points (22):** 15 required + 7 optional.

Required: `nvmlInit_v2`, `nvmlShutdown`, `nvmlErrorString`,
`nvmlSystemGetDriverVersion`, `nvmlSystemGetNVMLVersion`,
`nvmlDeviceGetCount_v2`, `nvmlDeviceGetHandleByIndex_v2`,
`nvmlDeviceGetName`, `nvmlDeviceGetUUID`, `nvmlDeviceGetPciInfo_v3`,
`nvmlDeviceGetMemoryInfo`, `nvmlDeviceGetUtilizationRates`,
`nvmlDeviceGetTemperature`, `nvmlDeviceGetPowerUsage`,
`nvmlDeviceGetClockInfo`.

Optional (absence or `NVML_ERROR_NOT_SUPPORTED` -> sentinel `-1`, except
`serial` -> `""`): `nvmlDeviceGetSerial`,
`nvmlDeviceGetPowerManagementLimit`, `nvmlDeviceGetEnforcedPowerLimit`,
`nvmlDeviceGetFanSpeed`, `nvmlDeviceGetCurrPcieLinkGeneration`,
`nvmlDeviceGetCurrPcieLinkWidth`, `nvmlDeviceGetTotalEnergyConsumption`.

**Constants / sizes:** `NVML_SUCCESS = 0`, `NVML_ERROR_NOT_SUPPORTED = 3`,
`NVML_ERROR_NOT_FOUND = 6`, `NVML_ERROR_DRIVER_NOT_LOADED = 9`,
`NVML_ERROR_LIBRARY_NOT_FOUND = 12`; temperature sensor `GPU = 0`; clocks
`GRAPHICS = 0`, `SM = 1`, `MEM = 2`; buffers 80 (system versions, UUID),
64 (name), 30 (serial), 32 (PCI bus id), legacy bus id 16.

**Struct layout (asserted at compile time):**

| Struct | Size | Key offsets |
|--------|------|-------------|
| `nvmlPciInfo_t` | 68 | `domain` 16, `bus` 20, `device` 24, `pciDeviceId` 28, `pciSubSystemId` 32, `busId` 36 |
| `nvmlMemory_t` | 24 | `total` 0, `free` 8, `used` 16 |
| `nvmlUtilization_t` | 8 | `gpu` 0, `memory` 4 |

**Local sample (NOT the pin; nothing committed):** System32 `nvml.dll`,
1,499,368 B, file version 8.17.16.1692 (NVML 616.92), SHA256
`AC08344786840363012B31409A62529D6C53EF2658C68D190BA8C3F1FE7C24A2`.
Recorded runtime: driver **616.92**, NVML **13.616.92**, 1 device,
`NVIDIA GeForce RTX 3070 Ti`, UUID
`GPU-51e6fb27-4bd4-2a99-a474-ce35f388d1c1`, PCI `00000000:08:00.0`,
8,589,934,592 B total memory, 49 C, ~95 W, graphics/SM 1875 MHz, memory
9501 MHz, fan 54%, PCIe 4 x16, energy ~39.6 MJ. Serial is
**NOT_SUPPORTED** on this card (empty string) -- the optional policy below
covers it.

### Re-pin procedure

1. Re-verify the entry-point names and struct layouts against a newer NVML
   header; update the offsets/asserts and the oracle hash in
   `PROVENANCE.md`.
2. Update the sample row and the recorded runtime values here and in
   `README.md`/`AUDIT.md`.
3. Re-run `scripts/port.ps1 -Package xiom.nvml` x2 and record
   `STATUS.json`.

## 3. Declared surface (100% of 0.1.0)

### 3.1 Public functions

| Function | Contract |
|----------|----------|
| `nvml_system() -> Result[NvmlSystem, NvmlError]` | Load `nvml.dll`, initialize, read driver + NVML versions and the device count, shut down. |
| `nvml_system_named(dll: Str)` | Same against a named module (deterministic SKIP path). |
| `nvml_device(index: Int) -> Result[NvmlDevice, NvmlError]` | Load/init, resolve `index`, query one full telemetry snapshot, shut down. |
| `nvml_device_named(dll: Str, index: Int)` | Same against a named module (deterministic SKIP path). |
| `nvml_is_skip(&NvmlError) -> Bool` | SKIP classifier: `LOAD_ABSENT`, `DRIVER_ABSENT`, `NO_DEVICE`. |
| `nvml_summary(&NvmlDevice) -> Str` | One-line human-readable telemetry summary. |

### 3.2 Snapshot fields (28 device + 3 system)

| Area | Fields | Coverage |
|------|--------|----------|
| System | driver_version, nvml_version, device_count | 3/3 |
| Identity | index, name, uuid, serial (optional), bus_id | 5/5 |
| PCI | domain, bus, device, ids_raw, vendor_id, device_id, subsystem_id | 7/7 |
| Memory | total, free, used (bytes) | 3/3 |
| Utilization | gpu %, memory % | 2/2 |
| Thermal | GPU-die temperature (C) | 1/1 |
| Power | usage mW, management limit mW, enforced limit mW | 3/3 |
| Clocks | graphics, SM, memory (MHz) | 3/3 |
| Fan | speed % | 1/1 |
| PCIe | current link generation, current link width | 2/2 |
| Energy | total consumption mJ | 1/1 |

`pciDeviceId` from NVML is a combined word: the bridge decomposes it into
`pci_vendor_id` (low 16 bits, 0x10DE on NVIDIA cards) and `pci_device_id`
(high 16 bits, 0x2482 on the RTX 3070 Ti), keeping `pci_ids_raw`.

## 4. Optional-metric policy

A declared optional metric is reported as `-1` when the entry point predates
the ABI pin or the driver returns `NVML_ERROR_NOT_SUPPORTED` /
`NVML_ERROR_NOT_FOUND`. `serial` is `""` in that case. All required metrics
fail the call (`NVML_API_FAILED`) on any other return code. The suite asserts
the live host values and the sentinel only where the host actually supports
the metric.

## 5. Typed errors

`NvmlError { kind, stage, code, message }`:

| Kind | Class | Meaning |
|------|-------|---------|
| `NVML_LOAD_ABSENT` (0) | SKIP | `nvml.dll` missing |
| `NVML_DRIVER_ABSENT` (1) | SKIP | driver not loaded / NVML unavailable |
| `NVML_NO_DEVICE` (2) | SKIP | no NVIDIA device |
| `NVML_BAD_INDEX` (3) | FAIL | index out of range |
| `NVML_ABI` (4) | FAIL | required entry point missing from a present DLL |
| `NVML_API_FAILED` (5) | FAIL | a declared query failed (raw code in `code`) |
| `NVML_INTERNAL` (6) | FAIL | bridge/internal failure |

`stage` names the operation (load, init, driver-version, nvml-version,
device-count, device-handle, name, uuid, serial, pci, memory, utilization,
temperature, power, power-limit, enforced-power-limit, clocks, fan, pcie,
energy, shutdown).

## 6. Live evidence (v0.64.6, RTX 3070 Ti, driver 616.92)

`scripts/port.ps1 -Package xiom.nvml -TimeoutSec 180` x2 -> **40/40 pass**.

- System: driver 616.92, NVML 13.616.92, 1 device.
- Identity: `NVIDIA GeForce RTX 3070 Ti`, UUID
  `GPU-51e6fb27-4bd4-2a99-a474-ce35f388d1c1`, PCI `00000000:08:00.0`,
  vendor 0x10DE, device 0x2482.
- Memory: 8,589,934,592 B total; free/used move between runs (other GPU
  workloads) and stay within total.
- Utilization/thermal: GPU 2-3%, 49 C.
- Power: ~95,000 mW usage, 310,000 mW limit and enforced limit.
- Clocks: 1875 / 1875 / 9501 MHz; fan 54%; PCIe 4 x16.
- Energy: ~39.5e9 mJ.
- Bounds: index 9999 -> `NVML_BAD_INDEX`.
- Stability: repeated snapshots agree on identity and total memory.

## 7. Deliberately not declared in 0.1.0

- Process enumeration (`nvmlDeviceGet*RunningProcesses`), MIG, vGPU,
  NVLink, ECC, retired pages, row-remapper and topology queries.
- Memory v2 (`reserved`), throttling reasons, performance states, dynamic
  P-state sampling, clock control, power capping, fan control and any other
  mutating API.
- Events/callbacks, NVML events, `nvmlDeviceSet*`, `nvmlDeviceReset*`.
- `nvmlDeviceGetTemperatureV` (the deprecated per-sensor call is the
  declared ABI).
- Linux soname (`libnvidia-ml.so.1`) and multi-device iteration helpers;
  `nvml_device(index)` already covers indices the caller enumerates.

## 8. Test contract

Suite: `tests/test_conformance.xi` -- 40 checks: SKIP classifier (5),
deterministic SKIP paths (2), live system snapshot (3), live device
identity/telemetry (27), bounds (1) and snapshot stability (2 live-only
checks; the non-live path reports SKIP).

Command (cwd = this package directory; the runner hook adds the C source):

```
scripts/port.ps1 -Package xiom.nvml -TimeoutSec 180
```

Watchdog: allow >=180 s (one small C TU; ~4 s on the development machine).

## 9. Design boundary (G5)

`nvml.xi` is the only module with `unsafe`/`extern "C"`; it calls the
integer-only bridge `nvml_bridge.c`, which loads `nvml.dll` at run time,
resolves every entry point with `GetProcAddress`, runs one snapshot query and
caches the results in static buffers. No foreign pointer or handle crosses
the FFI; each call initializes and shuts NVML down. Calls are not reentrant
by design (one cached snapshot).
