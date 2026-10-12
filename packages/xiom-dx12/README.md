# xiom.dx12

Direct3D 12 **foundation bindings** for XIOM. The package resolves
`d3d12.dll` at runtime through a tiny vendored C bridge (hand-rolled COM --
no `d3d12.h` include; the ABI is pinned from `microsoft/DirectX-Headers` in
`PROVENANCE.md`) and reports a staged capability probe:

1. **symbols** -- `D3D12CreateDevice` resolved
2. **device** -- `D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0,
   IID_ID3D12Device)` + `ID3D12Device::GetNodeCount` (vtable slot 7)
3. **object** -- `ID3D12Device::CreateCommandAllocator` (slot 9) out-param
   interface roundtrip, then `Release`

Missing runtime -> **SKIP**; no D3D12-capable adapter -> **SKIP**; present
but broken exports -> **FAIL**. CI stays green without a GPU.

> **Status:** `incubating` -- suite green **5/5 x2** on the pin (v0.64.4):
> D3D12 device created on an NVIDIA RTX 3070 Ti (node_count=1), allocator
> roundtrip + release, plus a deterministic SKIP-path test. **0.1.0 published
> in `eco-v0.1.166` (sha256 `5ff65bed...`).** **The full
> generated surface (all `ID3D12*` interfaces + free functions + enums/struct
> metadata from the pinned headers, plus DXGI) is the 0.2.0 wave.**
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.dx12;

fn main() {
  let p = dx12_probe();
  if !p.is_ok {
    // DX12_LOAD_ABSENT / DX12_LOAD_NO_DEVICE -> skip cleanly
    io.println("D3D12 unavailable: " + p.error.message);
    dx12_unload();
    return;
  }
  let info: Dx12DeviceInfo = p.value;
  io.println("device nodes: " + int_to_string(info.node_count));
  dx12_unload();
}
```

## API

| Area | Functions |
|------|-----------|
| Probe | `dx12_probe`, `dx12_probe_named(soname)`, `dx12_unload` |
| Types | `Dx12DeviceInfo` (node_count/allocator_ok), `Dx12ProbeError` (kind/message) |
| Kinds | `DX12_LOAD_ABSENT`, `DX12_LOAD_NO_DEVICE`, `DX12_LOAD_ABI` |
| Constants | `D3D_FEATURE_LEVEL_*`, `D3D12_COMMAND_LIST_TYPE_*`, `DX12_SONAME` |

## Build note

The bridge is compiled by the runner hook
(`port.args.json`: `--c-source ${PACKAGE_DIR}/src/dx12_probe.c`). Direct runs:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\dx12_probe.c
```

## Tests

```
scripts/port.ps1 -Package xiom.dx12
```

Expected: 5 `[PASS]`, exit 0, on a D3D12-capable desktop (device + node
count + allocator roundtrip); absent/no-adapter hosts collapse to SKIP
markers. See `SPEC.md` for the pin and `PROVENANCE.md` for the ABI source.
