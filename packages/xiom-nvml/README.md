# xiom.nvml

NVIDIA **NVML** (Management Library) telemetry bindings for XIOM.
`nvml.dll` ships with the NVIDIA display driver and is loaded at runtime;
**nothing is vendored**.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.6; 40/40 x2, live RTX 3070 Ti: driver 616.92, NVML 13.616.92,
> identity + memory + utilization + thermal + power + clocks + fan + PCIe +
> energy). **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.nvml;

fn main() {
  let s = nvml_system();
  if s.is_ok {
    io.println("driver " + s.value.driver_version
      + ", NVML " + s.value.nvml_version);
  } else if nvml_is_skip(&s.error) {
    io.println("SKIP: " + s.error.message);
  }

  let d = nvml_device(0);
  if d.is_ok {
    io.println(nvml_summary(&d.value));
  } else if nvml_is_skip(&d.error) {
    io.println("SKIP: " + d.error.message);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| System | `nvml_system`, `nvml_system_named(dll)` -> `NvmlSystem` (driver_version, nvml_version, device_count) |
| Device | `nvml_device(index)`, `nvml_device_named(dll, index)` -> `NvmlDevice` (28 fields) |
| Helpers | `nvml_is_skip(&NvmlError)`, `nvml_summary(&NvmlDevice)` |
| Kinds | `NVML_LOAD_ABSENT`, `NVML_DRIVER_ABSENT`, `NVML_NO_DEVICE` (SKIP), `NVML_BAD_INDEX`, `NVML_ABI`, `NVML_API_FAILED`, `NVML_INTERNAL` (FAIL) |

Metrics: driver/NVML versions, device count, name/UUID/serial/PCI identity,
memory total/free/used, GPU + memory utilization, GPU temperature, power
usage/limit/enforced limit, graphics/SM/memory clocks, fan speed, PCIe link
generation/width, total energy. Optional metrics are `-1` when the driver
reports `NVML_ERROR_NOT_SUPPORTED` (serial is `""`); see `SPEC.md` section 4.
Details and the ABI pin: `SPEC.md`; provenance: `PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.nvml -TimeoutSec 180
```

Expected: 40 `[PASS]`, exit 0 (or SKIP lines on a host without an NVIDIA
driver/GPU).

**Published:** `0.1.0` in `eco-v0.1.199` (sha256 `0aa65326...`, 2026-10-18; registry live-verified).
