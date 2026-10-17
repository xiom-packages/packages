# ROADMAP: xiom.nvapi

## 0.1.0 (shipped in-lane)

Load `nvapi64.dll`; resolve the id set through `nvapi_QueryInterface`;
initialize/unload; interface + driver versions and branch; physical GPU
enumeration; GPU 0 identity (name, PCI identifiers, bus id); GPU-die
temperature and graphics utilization. Typed errors, deterministic SKIP
paths, live RTX 3070 Ti suite.

## 0.2.x

- **All physical GPUs:** per-index identity/telemetry, keeping handles in C.
- **Clocks and power (read-only):** `NvAPI_GPU_GetAllClockFrequencies`,
  `NvAPI_GPU_GetPstatesInfoEx`, thermal thresholds, fan level readback.
- **Driver settings readback:** `NvAPI_DRV_GetDriverSettings` (read-only).
- **USB-C / power delivery telemetry** where the card exposes it.

## 0.3.x (platform)

- Linux path: NVAPI does not ship an official Linux runtime; document the
  unsupported platform explicitly and keep NVML (`xiom.nvml`) as the Linux
  telemetry path.
- Headless/TCC presentation flags and `NvAPI_GPU_GetArchInfo` /
  `NvAPI_GPU_GetVbiosVersionString` identity enrichment.

## Out of scope

Display topology/EDID, D3D/GL interop, I2C, SLI/stereo/surround/GSync and
all mutating driver settings. Separate decision if a consumer asks.

## Re-carve cadence

Refresh the `NVIDIA/nvapi` oracle at each SDK refresh; re-verify the ids,
struct versions and status values, run the suite x2, record `STATUS.json`.
