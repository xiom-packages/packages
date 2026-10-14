# xiom.rtxgi

NVIDIA RTXGI-DDGI (v1.3.7) integration surface for XIOM -- **reference-only
dynamic-loader binding** (`keywords: ["binding"]`).

Upstream was expected to be MIT; verification in the clone found the
proprietary **NVIDIA RTX SDKs License** instead (see `PROVENANCE.md`), so
nothing from RTXGI ships here -- no source, headers, shader blobs or
binaries. The package is independent XIOM code plus an XIOM-side bridge
(`src/rtxgi_bridge.cpp`, ours) that resolution-loads a locally built sample
module (`xiom_rtxgi_shim.dll`) and classifies **SKIP** when it is absent.
**Published**: `0.1.0` in `eco-v0.1.179` (sha256 `60833288...`).

## Surface (0.1.0)

- `DDGIVolumeDesc` (38 fields) as an owned image with defaults + setters/getters
- `GetDDGIVolumeProbeCounts`, `GetDDGIVolumeTextureDimensions` (6 texture types)
- descriptor counts (2 RTV / 6 Tex2DArray / 12 resource)
- `ValidateShaderBytecode`, `SetInsertPerfMarkers` / `bInsertPerfMarkers`
- volume lifecycle: create, `Update` (RNG ray rotation + scrolling), `Destroy`
- `GetDescGPU` (typed record) / `GetDescGPUPacked` (128B owned image)
- counts, ray dispatch dimensions, GPU memory sizing, probe world positions,
  AABB/OBB, euler-angle rotation
- typed error codes and the typed GPU-execution classification
  (`RTXGI_EXEC_NO_DEVICE` SKIP; no device bridge in 0.1.0)

## Usage

```xiom
use xiom.rtxgi;

let mod = rtxgi_load();                    // Err(kind = RTXGI_LOAD_ABSENT) when no shim
if mod.is_ok {
  let d = rtxgi_desc_for_volume(3, 2, 4, 256, 8, 16);
  // ... set origin/spacing via rtxgi_desc_set_f32_at ...
  let vol = rtxgi_volume_create(&mod.value, &d.value);
  if vol.is_ok {
    let _ = rtxgi_volume_update(&vol.value);
    let gpu = rtxgi_volume_gpu_desc(&vol.value);
    let _ = rtxgi_volume_destroy(&vol.value);
  }
  let _ = rtxgi_close(&mod.value);
}
```

## Test

```
.\scripts\port.ps1 -Package xiom.rtxgi -TimeoutSec 240
```

Green either way: without the shim module all runtime checks report
`SKIP (no RTXGI shim module present)` and stay green (classified platform
state); with `XIOM_RTXGI_SHIM` pointing at a locally built
`xiom_rtxgi_shim.dll`, the full surface executes (see `SPEC.md` sec. 6).

## Docs

- `SPEC.md` -- declared surface, coverage, loader model, run procedure
- `PROVENANCE.md` -- upstream pin, license finding, declaration oracle, shim sample
