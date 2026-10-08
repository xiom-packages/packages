# xiom.directx11

Direct3D 11 / DXGI **capability probe** for XIOM via a dynamic loader:
`d3d11_probe()` resolves `d3d11.dll` + `dxgi.dll` at runtime (no SDK headers,
no import libraries, no link-time dependency), creates a hardware device and
reports the feature level plus the first DXGI adapter.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1): 5/5 with
> an NVIDIA RTX 3070 Ti (device at feature level 11_0, 3 adapters), SKIP
> classification exercised every run.
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.directx11;

fn main() {
  let p = d3d11_probe();
  if !p.is_ok {
    io.println("D3D11 unavailable: " + p.error.message);  // SKIP in CI
    return;
  }
  let info: D3d11Info = p.value;
  io.println("device at feature level " + d3d11_feature_level_name(info.feature_level));
  io.println("adapter: " + info.adapter_name);
}
```

## API

| Area | Functions |
|------|-----------|
| Probe | `d3d11_probe`, `d3d11_probe_named(d3d11_soname, dxgi_soname)` |
| Types | `D3d11Info` (feature_level, adapter_name, vendor_id, device_id, adapter_count), `D3d11LoadError` |
| Kinds | `D3D11_LOAD_ABSENT`, `D3D11_LOAD_NO_DEVICE`, `D3D11_LOAD_ABI` |
| Helpers | `d3d11_feature_level_name`, `D3D_FEATURE_LEVEL_*`, `D3D11_SONAME`, `DXGI_SONAME` |

Failure model: libraries missing -> SKIP; no hardware device -> SKIP; entry
points missing -> FAIL. A bogus soname exercises the SKIP path
deterministically.

## Build note

`port.args.json` compiles the header-free probe bridge
(`--c-source ${PACKAGE_DIR}/src/d3d11_probe.c`); no `--link` flags. Direct run:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\d3d11_probe.c
```

## Tests

```
scripts/port.ps1 -Package xiom.directx11
```

Expected: 5 `[PASS]`, exit 0 (hardware device + adapter name). G2 pin +
re-pin: `SPEC.md` §2.
