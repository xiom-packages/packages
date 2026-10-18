# xiom.nvapi

NVIDIA **NVAPI** presence/identity/telemetry bindings for XIOM.
`nvapi64.dll` ships with the NVIDIA display driver and is loaded at runtime;
**nothing is vendored**. NVAPI exports only `nvapi_QueryInterface`; every
declared entry point is resolved by its numeric function id.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.6; 25/25 x2, live RTX 3070 Ti: interface 1.10, driver 616.92
> branch r616_69, GPU identity, 49 C, GPU utilization). **Lane:** bindings
> (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.nvapi;

fn main() {
  let p = nvapi_probe();
  if p.is_ok {
    io.println(nvapi_summary(&p.value));
  } else if nvapi_is_skip(&p.error) {
    io.println("SKIP: " + p.error.message);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Probe | `nvapi_probe`, `nvapi_probe_named(dll)` -> `NvapiInfo` (16 fields) |
| Helpers | `nvapi_is_skip(&NvapiError)`, `nvapi_summary(&NvapiInfo)` |
| Kinds | `NVAPI_LOAD_ABSENT`, `NVAPI_DRIVER_ABSENT`, `NVAPI_NO_DEVICE` (SKIP), `NVAPI_ABI`, `NVAPI_API_FAILED`, `NVAPI_INTERNAL` (FAIL) |

Snapshot: interface version; driver raw/major/minor/branch; physical GPU
count; GPU 0 name, PCI vendor/device/revision/subsystem/extended ids, bus id;
GPU-die temperature and graphics utilization (optional `-1` on
`NVAPI_NOT_SUPPORTED`). Details and the id pin: `SPEC.md`; provenance:
`PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.nvapi -TimeoutSec 180
```

Expected: 25 `[PASS]`, exit 0 (or a SKIP line on a host without an NVIDIA
driver/GPU).

**Published:** `0.1.0` in `eco-v0.1.199` (sha256 `80873598...`, 2026-10-18; registry live-verified).
