# xiom.optix

NVIDIA OptiX ray-tracing engine bindings for XIOM, built with the
reference-only dynamic-loader pattern: the OptiX SDK is **not vendored**, the
user's display-driver runtime (`nvoptix.dll`) is loaded at run time, and the
suite is SKIP-safe when it is absent.

The full OptiX SDK download is registration-gated (NVIDIA Developer Program).
This package therefore ships the loader, the declared essentials and the
acquisition contract in `PROVENANCE.md`; it does **not** fake a build or ship
any NVIDIA header, library or binary.

## What you get (0.1.0)

- **Device context**: create with options (validation mode, log level, disk
  cache on/off and location), validate (RT core version, max trace depth,
  cache state, device name), destroy.
- **Module load**: PTX module with the launch-params variable name/size;
  compiler failures come back as typed module errors carrying the OptiX log.
- **Program groups**: raygen, miss (including the null-miss form) and
  hitgroup (closest-hit) creation/destruction.
- **SBT build**: one record per supplied group, header packed by the
  runtime, header + user data rounded to the 16-byte SBT alignment, uploaded
  to the device; record readback for verification.
- **Pipeline**: create/link with the supplied groups, launch-params size and
  max trace depth; link failures carry the runtime validation log.
- **Launch params buffer**: device allocation plus host-to-device and
  device-to-host copies through owned `Vec[UInt8]` slots.
- **Launch**: `optixLaunch` on the default stream with a synchronize, so
  launch failures surface as typed errors.
- **Typed errors**: 13 kinds + native `OptixResult` code + message; missing
  runtime / no CUDA device are SKIP; an ABI mismatch is a FAIL.

Pinned ABI: **OptiX 9.1, `OPTIX_ABI_VERSION` 118** (see `SPEC.md`).

## Runtime model

```xiom
use xiom.optix;

let probe = optix_probe();
if probe.is_ok {
  let options = OptixContextOptions{
    validation_mode: false;
    log_level: 0;
    cache_enabled: true;
    cache_location: "",
  };
  let ctx = optix_context_create(options);
  if ctx.is_ok {
    // module = optix_module_load(ctx.value, ptx_text, "optixLaunchParams", 64)
    // raygen = optix_program_group_create(ctx.value, module.value, "__raygen__", 0)
    // miss   = optix_program_group_create(ctx.value, OptixModule{ handle: 0 }, "", 1)
    // sbt    = optix_sbt_build(ctx.value, raygen.value, miss.value, none, 64)
    // params = optix_params_create(ctx.value, 64)
    // pipe   = optix_pipeline_create(...)
    // ok     = optix_launch(pipe.value, params.value, sbt.value, 640, 360, 1)
    let _ = optix_context_destroy(ctx.value);
  }
} else {
  // probe.error.kind == OPTIX_ERR_LOADER_ABSENT or OPTIX_ERR_NO_DEVICE: SKIP
}
```

The full happy path needs a user-supplied PTX module (for example from the
SDK samples or your own nvcc build). The package suite proves the live
context/options/module-error/program-group/SBT/pipeline-validation/params
legs on an RTX host; the raygen launch is gated on that user PTX.

## Runtime acquisition (user-supplied)

1. Install a recent NVIDIA display driver (R590 or newer for OptiX 9.1).
   `nvoptix.dll` is a driver component; do not copy it into the repository.
2. Optional, for the full SDK (samples, PTX authoring, docs): download the
   OptiX SDK from
   <https://developer.nvidia.com/designworks/optix/download> with an NVIDIA
   Developer Program account and install it under `E:\repos\optix` (or
   wherever you keep SDKs). Nothing from it is committed.
3. The public header subset published by NVIDIA at
   <https://github.com/NVIDIA/optix-dev> (tag `v9.1.0`) is the declaration
   oracle used here; it is also not committed.

Loader search order: explicit `optix_probe_named(path)` only; otherwise
`XIOM_OPTIX_DLL`, the module search path (`nvoptix.dll`), the two
`NVIDIA Corporation\OptiX\bin` locations, `%SystemRoot%\System32`, then the
newest `nv_dispi.inf_amd64_*\nvoptix.dll` in the DriverStore. Set
`XIOM_OPTIX_NO_AUTO=1` to force the deterministic SKIP path on a host that
does have a driver (used by the SKIP-safe run evidence).

## Verify

```
.\scripts\port.ps1 -Package xiom.optix -TimeoutSec 300
```

Live host (NVIDIA RTX): 37/37 PASS. Runtime absent: 15/15 PASS with the live
legs reported as SKIP. See `AUDIT.md`, `docs/COVERAGE.md`, `SPEC.md`
(surface and pin), `PROVENANCE.md` (license/acquisition) and `ROADMAP.md`
(Phase 2).

**Published:** `0.1.0` in `eco-v0.1.199` (sha256 `012dd8b6...`, 2026-10-18; registry live-verified).
