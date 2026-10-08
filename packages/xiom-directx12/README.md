# xiom.directx12

Direct3D 12 / DXGI **capability probe** for XIOM via a dynamic loader:
`d3d12_probe()` resolves `d3d12.dll` + `dxgi.dll` at runtime (no SDK headers,
no import libraries, no link-time dependency), enumerates DXGI adapters and
reports the highest accepted D3D feature level.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1): 5/5 with
> an NVIDIA RTX 3070 Ti (highest accepted level **12_2**, 3 adapters), SKIP
> classification exercised every run.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.directx12;

fn main() {
  let p = d3d12_probe();
  if !p.is_ok {
    io.println("D3D12 unavailable: " + p.error.message);  // SKIP in CI
    return;
  }
  let info: D3d12Info = p.value;
  io.println("device accepts feature level " + d3d12_feature_level_name(info.feature_level));
  io.println("adapter: " + info.adapter_name);
}
```

## API

| Area | Functions |
|------|-----------|
| Probe | `d3d12_probe`, `d3d12_probe_named(d3d12_soname, dxgi_soname)` |
| Types | `D3d12Info` (feature_level, adapter_name, vendor_id, device_id, adapter_count), `D3d12LoadError` |
| Kinds | `D3D12_LOAD_ABSENT`, `D3D12_LOAD_NO_DEVICE`, `D3D12_LOAD_ABI` |
| Helpers | `d3d12_feature_level_name`, `D3D_FEATURE_LEVEL_*`, `D3D12_SONAME`, `DXGI_SONAME` |

Failure model: libraries missing -> SKIP; no D3D12 device -> SKIP; entry
points missing -> FAIL. The highest accepted feature level is determined by
descending `D3D12CreateDevice` attempts (12_2 -> 11_0).

## Build note

`port.args.json` compiles the header-free probe bridge
(`--c-source ${PACKAGE_DIR}/src/d3d12_probe.c`); no `--link` flags. Direct run:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\d3d12_probe.c
```

## Tests

```
scripts/port.ps1 -Package xiom.directx12
```

Expected: 5 `[PASS]`, exit 0 (highest level 12_2 + adapter name). G2 pin +
re-pin: `SPEC.md` §2.
