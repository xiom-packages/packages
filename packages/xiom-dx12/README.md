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

> **Status:** `incubating` -- **0.3.0 struct metadata + full core surface**:
> suite green **18/18 x2** on the pin (v0.64.4): the full `d3d12.h` core
> surface -- 90 interfaces / 358 generated method wrappers (355 standard +
> 3 callback-param) / 1162 enum consts / 9 free functions -- **plus the
> struct-metadata wave**: 19 typed shims for the sret/by-value shapes
> (GetDesc-family, GetResourceAllocationInfo, by-value `D3D12_NODE_ID`),
> 240 struct sizes + 863 member offsets as `D3D12_SIZEOF_*`/`D3D12_OFF_*`
> constants (`struct_meta_1..3`), and oracle-vs-build sizeof cross-checks.
> Driven live on an NVIDIA RTX 3070 Ti: device + node count, queue creation
> + `GetDesc` sret roundtrip, committed-buffer `GetDesc`, allocation info
> (65536/65536), custom-heap properties, root-signature serialization
> (88-byte blob), plus the 0.1.0 probe + SKIP classification.
> DXGI (factory/adapters/WARP/swapchain) is the next wave (`ROADMAP.md`).
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

## Generated surface (0.3.0)

`tools/gen_dx12.py` parses the pinned `d3d12.h` and emits the full core
surface into `src/`:

| Set | Count | Modules |
|-----|-------|---------|
| Interface method wrappers (own methods, absolute vtable slots) | 358 | `iface_01..12` |
| Enum consts | 1162 | `consts_1..5` |
| Free functions (`D3D12SerializeRootSignature`, `D3D12CreateDevice`, ...) | 9 | `functions` |
| Typed shims (sret / by-value normal forms) + sizeof probes | 19 + 16 | `structs` (+ `src/d3d12_structs.c`) |
| Struct sizes + member offsets | 1103 | `struct_meta_1..3` |

Wrapper names are `d3d12_<iface>_<method>` (e.g.
`d3d12_device_create_command_queue`,
`d3d12_graphics_command_list_draw_indexed_instanced`); each takes the COM
object pointer as `obj: Int`. Device methods need a live device:
`dx12_open_device()` keeps the runtime + device loaded, `dx12_unload()`
closes. Slot shims live in `src/d3d12_calls.c` (x64 vtable calls); free
functions resolve lazily via `xd12_resolve`.

**Struct normal forms (0.3.0):** the 19 struct-by-value methods that 0.2.0
skipped are emitted as typed shims in `src/d3d12_structs.c` with the C
bridge owning the ABI: sret methods write through a caller-owned slot
(`d3d12_resource_get_desc(obj, out_slot)`), by-value struct params arrive as
owned slot pointers, and the 3 callback-param methods (`D3D12*Func`) take a
raw handler address (`Int`; XIOM handler functions cannot cross to C yet --
B-22/B-23). Sizes + member offsets for 240 structs are emitted as
`D3D12_SIZEOF_<X>`/`D3D12_OFF_<X>_<MEMBER>` constants (the 55 skipped
shapes -- anonymous unions/bitfields/function-pointer members -- are listed
in `docs/struct_meta_manifest.json`). See `docs/COVERAGE.md` for counts and
the live witnesses.

## API

| Area | Functions |
|------|-----------|
| Probe | `dx12_probe`, `dx12_probe_named(soname)`, `dx12_open_device`, `dx12_unload` |
| Surface | generated `d3d12_<iface>_<method>` wrappers in `xiom.dx12.iface_01..12` (358); consts in `xiom.dx12.consts_1..5` (1162); free fns in `xiom.dx12.functions` (9); typed struct methods + `dx12_sizeof_*` probes in `xiom.dx12.structs`; `D3D12_SIZEOF_*`/`D3D12_OFF_*` in `xiom.dx12.struct_meta_1..3` |
| Types | `Dx12DeviceInfo` (node_count/allocator_ok), `Dx12ProbeError` (kind/message) |
| Kinds | `DX12_LOAD_ABSENT`, `DX12_LOAD_NO_DEVICE`, `DX12_LOAD_ABI` |
| Constants | `D3D_FEATURE_LEVEL_*`, `D3D12_COMMAND_LIST_TYPE_*`, `DX12_SONAME` |
| Helpers | `dx12_device_ptr`, `dx12_iid`, `dx12_blob_size`, `dx12_poke_u32/u64`, `dx12_null_ptr` (B-23 workaround) |

## Build note

The bridge is compiled by the runner hook (`port.args.json`:
`--c-source ${PACKAGE_DIR}/src/dx12_probe.c` + `d3d12_calls.c` +
`d3d12_structs.c`). Direct runs:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\dx12_probe.c \
  --c-source <abs>\src\d3d12_calls.c --c-source <abs>\src\d3d12_structs.c
```

## Tests

```
scripts/port.ps1 -Package xiom.dx12
```

Expected: 18 `[PASS]`, exit 0, on a D3D12-capable desktop (probe stages +
device/queue/root-signature + the 0.3.0 struct-metadata witnesses);
absent/no-adapter hosts collapse to SKIP markers. See `SPEC.md` for the pin
and `PROVENANCE.md` for the ABI source.
