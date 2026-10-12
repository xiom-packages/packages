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

> **Status:** `incubating` -- **0.3.0: struct metadata + full core + DXGI**:
> suite green **28/28 x2** on the pin (v0.64.4): the full `d3d12.h` core
> surface -- 90 interfaces / 358 generated method wrappers (355 standard +
> 3 callback-param) / 1162 enum consts / 9 free functions -- **plus the
> struct-metadata wave** (19 typed shims for the sret/by-value shapes; 272
> struct sizes + 1036 member offsets as `D3D12_SIZEOF_*`/`D3D12_OFF_*`/
> `DXGI_SIZEOF_*`/`DXGI_OFF_*` constants) **and the DXGI wave** (43 IDXGI
> interfaces / 163 wrappers / 6 free functions / 246 consts; factory +
> adapter enumeration + WARP + hidden-window BGRA8/FIFO swapchain).
> Driven live on an NVIDIA RTX 3070 Ti: device + node count, queue creation
> + `GetDesc` sret roundtrips, committed-buffer `GetDesc`, allocation info
> (65536/65536), custom-heap properties, root-signature serialization
> (88-byte blob), DXGI factory (3 adapters), adapter/WARP descs (vendor
> 0x10DE/0x1414), WARP D3D12 device, 640x480 BGRA8 swapchain + buffer +
> desc + present, plus probe/SKIP classification on both runtimes.
> `d3d12video.h` is the next slice (`ROADMAP.md`).
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

`tools/gen_dx12.py` parses the pinned `d3d12.h` plus the pinned DXGI SDK
headers (PROVENANCE.md) and emits both surfaces into `src/`:

| Set | Count | Modules |
|-----|-------|---------|
| D3D12 method wrappers (own methods, absolute vtable slots) | 358 | `iface_01..12` |
| D3D12 enum consts | 1162 | `consts_1..5` |
| D3D12 free functions | 9 | `functions` |
| Typed shims (sret / by-value normal forms) + sizeof probes | 19 + 16 | `structs` (+ `src/d3d12_structs.c`) |
| Struct sizes + member offsets (D3D12 + DXGI) | 1308 | `struct_meta_1..3` |
| DXGI method wrappers | 163 | `dxgi_iface_01..06` |
| DXGI enum consts | 246 | `dxgi_consts_1` |
| DXGI free functions | 6 | `dxgi_functions` |

Wrapper names are `d3d12_<iface>_<method>` / `dxgi_<iface>_<method>` (e.g.
`d3d12_device_create_command_queue`, `dxgi_swap_chain1_get_desc1`); each
takes the COM object pointer as `obj: Int`. Device methods need a live
device: `dx12_open_device()` keeps the runtime + device loaded;
`dxgi_open_factory()` keeps the DXGI factory live; matching `*_unload()`
closes. Slot shims live in `src/d3d12_calls.c` / `src/dxgi_calls.c` (x64
vtable calls); free functions resolve lazily via `xd12_resolve` /
`xd12_resolve_dxgi`.

**Struct normal forms (0.3.0):** the 19 struct-by-value methods that 0.2.0
skipped are emitted as typed shims in `src/d3d12_structs.c` with the C
bridge owning the ABI: sret methods write through a caller-owned slot
(`d3d12_resource_get_desc(obj, out_slot)`), by-value struct params arrive as
owned slot pointers, and the 3 callback-param methods (`D3D12*Func`) take a
raw handler address (`Int`; XIOM handler functions cannot cross to C yet --
B-22/B-23). Sizes + member offsets for 272 structs (D3D12 + DXGI) are
emitted as `D3D12_SIZEOF_*`/`DXGI_OFF_*`-family constants (the 57 skipped
shapes -- anonymous unions/bitfields/function-pointer members -- are listed
in `docs/struct_meta_manifest.json`). See `docs/COVERAGE.md` for counts and
the live witnesses.

**DXGI (0.3.0):** `dxgi.xi` (module `xiom.dx12.dxgi`) wraps the vendored
`src/dxgi_probe.c`: runtime `dxgi.dll` classification, factory creation
(`CreateDXGIFactory2`), adapter enumeration (`EnumAdapters1`), WARP adapter
(`IDXGIFactory4::EnumWarpAdapter` + a D3D12 device on it -- the adapter-less
fallback), and a hidden-window BGRA8/FIFO swapchain probe
(`CreateSwapChainForHwnd` -> `GetBuffer` -> `GetDesc1` -> `Present`).

## API

| Area | Functions |
|------|-----------|
| Probe | `dx12_probe`, `dx12_probe_named(soname)`, `dx12_open_device`, `dx12_unload` |
| Surface | generated `d3d12_<iface>_<method>` wrappers in `xiom.dx12.iface_01..12` (358); consts in `xiom.dx12.consts_1..5` (1162); free fns in `xiom.dx12.functions` (9); typed struct methods + `dx12_sizeof_*` probes in `xiom.dx12.structs`; `D3D12_SIZEOF_*`/`D3D12_OFF_*`/`DXGI_*` in `xiom.dx12.struct_meta_1..3` |
| DXGI | `dxgi_probe`, `dxgi_probe_named`, `dxgi_open_factory`, `dxgi_factory_ptr`, `dxgi_enum_adapter`, `dxgi_warp_adapter`, `dxgi_warp_device_probe`, `dxgi_swapchain_probe` + getters, `dxgi_iid`, `dxgi_unload` (module `xiom.dx12.dxgi`); generated wrappers in `xiom.dx12.dxgi_iface_01..06` (163); consts in `xiom.dx12.dxgi_consts_1` (246); free fns in `xiom.dx12.dxgi_functions` (6) |
| Types | `Dx12DeviceInfo` (node_count/allocator_ok), `Dx12ProbeError` (kind/message), `DxgiFactoryInfo` (adapter_count/warp), `DxgiProbeError` |
| Kinds | `DX12_LOAD_ABSENT`, `DX12_LOAD_NO_DEVICE`, `DX12_LOAD_ABI`, `DXGI_LOAD_ABSENT`, `DXGI_LOAD_ABI`, `DXGI_LOAD_FACTORY`, `DXGI_SWAPCHAIN_*` |
| Constants | `D3D_FEATURE_LEVEL_*`, `D3D12_COMMAND_LIST_TYPE_*`, `DX12_SONAME`, `DXGI_SONAME`, `DXGI_FORMAT_B8G8R8A8_UNORM`, `DXGI_SWAP_EFFECT_FLIP_DISCARD` |
| Helpers | `dx12_device_ptr`, `dx12_iid`, `dx12_blob_size`, `dx12_poke_u32/u64`, `dx12_null_ptr` (B-23 workaround) |

## Build note

The bridges are compiled by the runner hook (`port.args.json`:
`--c-source ${PACKAGE_DIR}/src/dx12_probe.c` + `d3d12_calls.c` +
`d3d12_structs.c` + `dxgi_probe.c` + `dxgi_calls.c`, and `--link user32` for
the swapchain's hidden window). Direct runs:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\dx12_probe.c \
  --c-source <abs>\src\d3d12_calls.c --c-source <abs>\src\d3d12_structs.c \
  --c-source <abs>\src\dxgi_probe.c --c-source <abs>\src\dxgi_calls.c \
  --link user32
```

## Tests

```
scripts/port.ps1 -Package xiom.dx12
```

Expected: 28 `[PASS]`, exit 0, on a D3D12-capable desktop (probe stages +
device/queue/root-signature + struct-metadata + DXGI factory/adapter/WARP/
swapchain witnesses); absent/no-adapter hosts collapse to SKIP markers. See
`SPEC.md` for the pins and `PROVENANCE.md` for the ABI sources.
