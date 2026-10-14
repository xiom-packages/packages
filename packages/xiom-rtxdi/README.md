# xiom.rtxdi

NVIDIA RTXDI (ReSTIR DI integration runtime, pinned tag v3.1.0 + runtime
library revision f12037fa) for XIOM -- **reference-only dynamic-loader
binding** (`keywords: ["binding"]`).

Upstream was expected to be MIT; verification in the clones found the
proprietary **NVIDIA RTX SDKs License** instead (see `PROVENANCE.md`), so
nothing from RTXDI ships here -- no source, headers, shader sources or
binaries. The package is independent XIOM code plus an XIOM-side bridge
(`src/rtxdi_bridge.cpp`, ours) that resolution-loads a locally built sample
module (`xiom_rtxdi_shim.dll`) and classifies **SKIP** when it is absent.
**Published**: `0.1.0` in `eco-v0.1.179` (sha256 `f1fabdcb...`).

## Surface (0.1.0)

- runtime utilities: reservoir buffer parameters, PDF texture sizing,
  neighbor offsets (R2 uint8 pairs), JenkinsHash
- `ReSTIRDIContext` lifecycle, resampling modes, frame index, and the full
  parameter set (runtime, buffer indices, initial/temporal/boiling/spatial/
  spatio-temporal/shading, static) as owned images, with the seven
  `GetDefault*` constructors
- frame plan composition (runtime params + buffer-index rotation + reservoir
  pitches) for dispatch/resource planning
- light/instance buffer setup: `RTXDI_LightBufferParameters` regions,
  `RISBufferSegmentAllocator`, `ReGIRContext` (grid + onion calculated
  parameters, dynamic parameters)
- top-level `ImportanceSamplingContext` (DI + ReGIR + RIS + neighbor setup,
  light buffer set/get, child handles)
- typed errors; typed GPU-execution classification (`RTXDI_EXEC_NO_DEVICE`
  SKIP; no device bridge in 0.1.0)

## Usage

```xiom
use xiom.rtxdi;

let mod = rtxdi_load();                    // Err(kind = RTXDI_LOAD_ABSENT) when no shim
if mod.is_ok {
  let di = rtxdi_di_create(&mod.value, 320, 180, RTXDI_CHECKERBOARD_OFF, 8192);
  if di.is_ok {
    let _ = rtxdi_di_set_frame_index(&di.value, 0);   // frame counter is app-driven
    let plan = rtxdi_frame_plan(&di.value);           // runtime + indices + reservoir pitches
    // ... size/allocate RIS buffers, copy plan images into constant buffers ...
    let _ = rtxdi_di_destroy(&di.value);
  }
  let _ = rtxdi_close(&mod.value);
}
```

## Test

```
.\scripts\port.ps1 -Package xiom.rtxdi -TimeoutSec 240
```

Green either way: without the shim module all runtime checks report
`SKIP (no RTXDI shim module present)` and stay green (classified platform
state); with `XIOM_RTXDI_SHIM` pointing at a locally built
`xiom_rtxdi_shim.dll`, the full surface executes (see `SPEC.md` sec. 6).

## Docs

- `SPEC.md` -- declared surface, coverage, loader model, run procedure
- `PROVENANCE.md` -- upstream pins, license finding, declaration oracle, shim sample
