# PROVENANCE: xiom.nvml

Per lane doctrine `docs/UPSTREAM-FIRST.md` (owner policy 2026-10-11).

## Upstream

| Field | Value |
|-------|-------|
| Project | **NVIDIA/go-nvml** -- https://github.com/NVIDIA/go-nvml (Apache-2.0 wrapper; contains NVIDIA's published NVML header) |
| Oracle file | `gen/nvml/nvml.h` -- NVML 13.4.92, from the CUDA redist `cuda_nvml_dev-linux-x86_64-13.4.92` |
| Upstream license | Repository Apache License 2.0; the header carries NVIDIA's standard NVML notice ("This source code is subject to NVIDIA ownership rights... users are hereby granted a nonexclusive, royalty-free license to use this code in individual and commercial software"). |
| Policy | **Reference-only. NEVER vendored.** The shipped package contains no header, no import library and no NVIDIA code. `nvml.dll` is a system component of the installed NVIDIA display driver and is loaded at run time. |
| Reference clone | `E:\repos\go-nvml` -- pinned commit `1a1e86da474d340d7cf58274588f4a4afc8772e7` (2026-10-06); light clone (`--depth 1`) retained locally, not committed |
| Package license | MIT OR Apache-2.0 (no upstream code copied into this package) |

The shipped surface is **independent XIOM + C code** written against the
public interface declarations in the pinned clone (the "declaration oracle"
below). The C bridge is original XIOM-side code; it encodes only interface
facts (function names/signatures, struct field order, enum values, buffer
sizes) and asserts every offset it relies on at compile time, so a header
move breaks the build loudly instead of corrupting a driver call.

## Declaration oracle (files read at the pinned commit)

| File | SHA256 |
|------|--------|
| `gen/nvml/nvml.h` | `2C35117E085411980D953BC3F3B532F13FE06F594F223E07ED80CF04959FD549` |

What the bridge takes from the header:

- Function names and signatures: `nvmlInit_v2`, `nvmlShutdown`,
  `nvmlErrorString`, `nvmlSystemGetDriverVersion`, `nvmlSystemGetNVMLVersion`,
  `nvmlDeviceGetCount_v2`, `nvmlDeviceGetHandleByIndex_v2`,
  `nvmlDeviceGetName`, `nvmlDeviceGetUUID`, `nvmlDeviceGetSerial`,
  `nvmlDeviceGetPciInfo_v3`, `nvmlDeviceGetMemoryInfo`,
  `nvmlDeviceGetUtilizationRates`, `nvmlDeviceGetTemperature`,
  `nvmlDeviceGetPowerUsage`, `nvmlDeviceGetPowerManagementLimit`,
  `nvmlDeviceGetEnforcedPowerLimit`, `nvmlDeviceGetClockInfo`,
  `nvmlDeviceGetFanSpeed`, `nvmlDeviceGetCurrPcieLinkGeneration`,
  `nvmlDeviceGetCurrPcieLinkWidth`, `nvmlDeviceGetTotalEnergyConsumption`.
- Struct layouts: `nvmlPciInfo_t`, `nvmlMemory_t`, `nvmlUtilization_t`.
- Enum values used: `nvmlReturn_t` success/not-supported/not-found/
  driver-not-loaded/library-not-found; `nvmlTemperatureSensors_t`
  `NVML_TEMPERATURE_GPU = 0`; `nvmlClockType_t` GRAPHICS/SM/MEM = 0/1/2.
- Buffer-size constants: name 64, UUID/system versions 80, serial 30,
  PCI bus id 32 (legacy 16).

## Derived vs independent

- `nvml.xi` (root module; all `unsafe`/`extern`): **independent** XIOM
  code -- typed errors, snapshot getters, the declared surface.
- `nvml_bridge.c`: **original XIOM-side helper** (ours, MIT OR Apache-2.0),
  compiled with `--c-source`; it never links NVIDIA code. It resolves every
  entry point with `LoadLibraryA`/`GetProcAddress`, keeps all foreign memory
  access in C, and guards the struct declarations with `_Static_assert`
  offsets/sizes.
- No upstream test vectors or media are imported; the live checks read the
  installed driver's real telemetry.

## Local runtime samples (present-path evidence; not the pin)

Host: NVIDIA GeForce RTX 3070 Ti, driver 616.92 (Windows driver version
32.0.16.1692), NVML 13.616.92.

| Module | Size | SHA256 |
|--------|------|--------|
| `C:\Windows\System32\nvml.dll` | 1,499,368 B | `AC08344786840363012B31409A62529D6C53EF2658C68D190BA8C3F1FE7C24A2` |

The suite reports the driver/NVML versions, device identity, memory,
utilization, temperature, power, clocks, fan, PCIe link and total energy.

## Re-carve procedure (upstream moves)

1. Refresh `E:\repos\go-nvml` at the new commit/tag; update the pin and the
   `E:\repos\CLEANUP.md` review date.
2. Re-hash `gen/nvml/nvml.h` into the table above; re-verify the struct
   offsets/sizes, enum values and signatures against the new header.
3. Update the `_Static_assert` block and the interface facts in
   `nvml_bridge.c` in the same commit as the pin update.
4. `scripts/port.ps1 -Package xiom.nvml -TimeoutSec 180` x2 (live RTX host);
   `scripts/status.ps1 -Action update`; conventional commit; sync
   `SPEC.md`/`AUDIT.md` counts in the same commit.
