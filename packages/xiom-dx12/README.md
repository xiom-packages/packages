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

> **Status:** `stable` -- promoted 2026-10-13 at **0.3.1** (gate evidence in
> `SPEC.md` sec. 7); **0.4.0 adds command recording**.  **Surface: struct
> metadata + full core + DXGI + video slice + recording**: suite green
> **42/42 x2** on the pin (v0.64.4). The surface: 90 D3D12 interfaces -> 358
> method wrappers + 19 typed shims, 1162 enum consts, 9 free functions; 43
> DXGI interfaces -> 163 wrappers, 246 consts, 6 free functions; 30 video
> (d3d12video.h) interfaces -> 190 wrappers, 661 consts, 10 typed shims;
> 434 struct sizes + 1804 member offsets (2238 meta consts). Live on an
> NVIDIA RTX 3070 Ti: device + node count, queue `GetDesc` sret roundtrips,
> committed-buffer `GetDesc`, allocation info (65536/65536), custom-heap
> properties, root-signature serialization, DXGI factory (3 adapters) +
> adapter/WARP descs + WARP D3D12 device + 640x480 BGRA8/FIFO swapchain
> (buffer/desc/present), video `ID3D12VideoDevice` QI + VIDEO_DECODE
> command list + generated `Close`, **command recording** (allocator/list
> lifecycle, submit, fence signal + wait), error paths (NULL blob guard,
> invalid queue priority / buffer layout rejected, out-of-range adapter
> index), plus probe/SKIP classification on all three runtimes. 0.1.0
> published in `eco-v0.1.166` (sha256 `5ff65bed...`); 0.2.0 in `eco-v0.1.167`
> (sha256 `7cfae765...`); 0.3.0 in `eco-v0.1.168` (sha256 `14ce3e67...`);
> 0.3.1 in `eco-v0.1.169` (sha256 `355ecc6d...`, stable). B-23/B-24
> workarounds are accepted with expiry = next compiler pin (see
> `docs/repro/bindings-pilot/`); B-25 makes COM object params cross as
> `Int`; callback-param methods take a raw handler address (B-22).
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
| Struct sizes + member offsets (D3D12 + DXGI + video) | 2238 | `struct_meta_1..5` |
| DXGI method wrappers | 163 | `dxgi_iface_01..06` |
| DXGI enum consts | 246 | `dxgi_consts_1` |
| DXGI free functions | 6 | `dxgi_functions` |
| Video method wrappers (d3d12video.h) | 190 | `video_iface_01..04` |
| Video enum consts | 661 | `video_consts_1..3` |
| Video typed shims (sret / by-value) | 10 | `video_structs` (+ `src/video_structs.c`) |

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
B-22/B-23). Sizes + member offsets for 434 shapes (D3D12 + DXGI + video)
are emitted as `D3D12_SIZEOF_*`/`DXGI_OFF_*`-family constants (the 97
skipped shapes -- anonymous unions/bitfields/function-pointer members -- are
listed in `docs/struct_meta_manifest.json`). See `docs/COVERAGE.md` for
counts and the live witnesses.

**DXGI (0.3.0):** `dxgi.xi` (module `xiom.dx12.dxgi`) wraps the vendored
`src/dxgi_probe.c`: runtime `dxgi.dll` classification, factory creation
(`CreateDXGIFactory2`), adapter enumeration (`EnumAdapters1`), WARP adapter
(`IDXGIFactory4::EnumWarpAdapter` + a D3D12 device on it -- the adapter-less
fallback), and a hidden-window BGRA8/FIFO swapchain probe
(`CreateSwapChainForHwnd` -> `GetBuffer` -> `GetDesc1` -> `Present`).

## Command recording (0.4.0)

```xiom
use xiom.dx12;
use xiom.dx12.recording;
use xiom.dx12.iface_03;   // the queue/allocator/list wrappers
use xiom.dx12.iface_02;   // ID3D12GraphicsCommandList

// Allocator (IID 1) + graphics command list (IID 4) on the live device:
//   d3d12_device_create_command_allocator(dev, 0, aiid, aslot);
//   d3d12_device_create_command_list(dev, 0, 0, alloc, 0, liid, lslot);
// Close, then submit and fence-signal:
d3d12_graphics_command_list_close(list);       // hr 0
dx12_execute_one(queue, list);                  // ExecuteCommandLists
d3d12_command_queue_signal(queue, fence, 1 as UInt64);
let r = dx12_fence_wait(fence, 1 as UInt64, 5000);   // 0 = signaled
```

COM object handles cross as **`Int`** (the generated params are typed so
-- B-25: `Int as *UInt8` is not value-preserving on v0.64.4; the
`Int`-param path is exact, witnessed by the suite's fidelity check).
`dx12_execute_one` builds the single-entry `ID3D12CommandList* const*`
array in an owned slot (B-24 discipline); `dx12_fence_wait` blocks on the
fence inside the bridge (Win32 event + `WaitForSingleObject`) and returns
`0` signaled / `1` timeout / `>= 2` error.

## API

| Area | Functions |
|------|-----------|
| Probe | `dx12_probe`, `dx12_probe_named(soname)`, `dx12_open_device`, `dx12_unload` |
| Surface | generated `d3d12_<iface>_<method>` wrappers in `xiom.dx12.iface_01..12` (358); consts in `xiom.dx12.consts_1..5` (1162); free fns in `xiom.dx12.functions` (9); typed struct methods + `dx12_sizeof_*` probes in `xiom.dx12.structs`; `D3D12_SIZEOF_*`/`D3D12_OFF_*`/`DXGI_*` in `xiom.dx12.struct_meta_1..5` |
| DXGI | `dxgi_probe`, `dxgi_probe_named`, `dxgi_open_factory`, `dxgi_factory_ptr`, `dxgi_enum_adapter`, `dxgi_warp_adapter`, `dxgi_warp_device_probe`, `dxgi_swapchain_probe` + getters, `dxgi_iid`, `dxgi_unload` (module `xiom.dx12.dxgi`); generated wrappers in `xiom.dx12.dxgi_iface_01..06` (163); consts in `xiom.dx12.dxgi_consts_1` (246); free fns in `xiom.dx12.dxgi_functions` (6) |
| Video | `dx12_video_probe`, `dx12_video_iid`, `dx12_video_cmdlist_create`/`_hr`/`_alloc`/`_cleanup` (module `xiom.dx12.video`); generated wrappers in `xiom.dx12.video_iface_01..04` (190); consts in `xiom.dx12.video_consts_1..3` (661); typed shims in `xiom.dx12.video_structs` (10) |
| Recording (0.4.0) | `dx12_execute_one(queue, list)` (module `xiom.dx12.recording`); root `dx12_fence_wait(fence, value, timeout_ms)`; the allocator/list/fence wrappers come from the generated surface (`iface_02`/`iface_03`) |
| Types | `Dx12DeviceInfo` (node_count/allocator_ok), `Dx12ProbeError` (kind/message), `DxgiFactoryInfo` (adapter_count/warp), `DxgiProbeError` |
| Kinds | `DX12_LOAD_ABSENT`, `DX12_LOAD_NO_DEVICE`, `DX12_LOAD_ABI`, `DXGI_LOAD_ABSENT`, `DXGI_LOAD_ABI`, `DXGI_LOAD_FACTORY`, `DXGI_SWAPCHAIN_*` |
| Constants | `D3D_FEATURE_LEVEL_*`, `D3D12_COMMAND_LIST_TYPE_*`, `DX12_SONAME`, `DXGI_SONAME`, `DXGI_FORMAT_B8G8R8A8_UNORM`, `DXGI_SWAP_EFFECT_FLIP_DISCARD` |
| Helpers | `dx12_device_ptr`, `dx12_iid`, `dx12_blob_size`, `dx12_poke_u32/u64`, `dx12_null_ptr` (B-23 workaround), `dx12_fence_wait`, `dx12_ptr_value`/`dx12_ptr_value_i` (fidelity diagnostics) |

## Build note

The bridges are compiled by the runner hook (`port.args.json`:
`--c-source ${PACKAGE_DIR}/src/dx12_probe.c` + `d3d12_calls.c` +
`d3d12_structs.c` + `dxgi_probe.c` + `dxgi_calls.c` + `video_probe.c` +
`video_calls.c` + `video_structs.c`, and `--link user32` for the swapchain's
hidden window). Direct runs:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\dx12_probe.c \
  --c-source <abs>\src\d3d12_calls.c --c-source <abs>\src\d3d12_structs.c \
  --c-source <abs>\src\dxgi_probe.c --c-source <abs>\src\dxgi_calls.c \
  --c-source <abs>\src\video_probe.c --c-source <abs>\src\video_calls.c \
  --c-source <abs>\src\video_structs.c --link user32
```

## Tests

```
scripts/port.ps1 -Package xiom.dx12
```

Expected: 42 `[PASS]`, exit 0, on a D3D12-capable desktop (probe stages +
device/queue/root-signature + struct-metadata + DXGI factory/adapter/WARP/
swapchain + video QI/command-list + command-recording witnesses + error
paths); absent hosts collapse to SKIP markers. See `SPEC.md` for the pins
and `PROVENANCE.md` for the ABI sources.
