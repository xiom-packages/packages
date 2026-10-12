# COVERAGE -- xiom.dx12 (slice 4: struct metadata + full D3D12 core + DXGI + video)

Oracles: `microsoft/DirectX-Headers` @ `461ef513` --
`include/directx/d3d12.h` (SHA256 `AFA193D3...`), `d3d12video.h`
(`9CCD140C...`), with `dxgicommon.h` / `dxgiformat.h` for member types;
DXGI from the Windows SDK 10.0.26100.0 shared headers (per-file SHA256 in
`PROVENANCE.md`).  Generators: `tools/gen_dx12.py` (surfaces + typed shims;
deterministic, Python stdlib only) and `tools/gen_dx12_struct_meta.py` (+
`tools/struct_dump.cpp` compiled with clang against the pinned headers ->
`docs/struct_dump.txt`; the dump needs
`-I <clone>\include\directx -I <SDK>\shared`).

## d3d12.h surface

| Set | Oracle | Emitted | Witness | Notes |
|-----|--------|---------|---------|-------|
| Interfaces | 90 | 90 | -- | all `MIDL_INTERFACE` blocks parsed; own methods = vtbl diff vs the base |
| Vtable rows (incl. inherited) | 2476 | -- | -- | absolute slot indices preserved in the shims |
| Own methods | 377 | **358 wrappers** | device/object/queue paths exercised live | 355 standard + 3 callback-param (`D3D12*Func` -> raw address); **0 unmapped** |
| Typed shims (struct-by-value normal forms) | 19 | **19 shims** | queue/resource `GetDesc` sret, `GetResourceAllocationInfo`, `GetCustomHeapProperties` live | sret via caller-owned slot; by-value `D3D12_NODE_ID` params via owned slot pointer |
| Enums | 1162 values | **1162 consts** | sanity-checked (`D3D12_FILL_MODE_SOLID`, `D3D12_HEAP_TYPE_*`, `D3D12_RESOURCE_STATE_COMMON`) | expression-evaluated |
| Free functions | 9 | **9 wrappers** | serialized a 1-root-constant signature | lazy resolve via `xd12_resolve` |

## dxgi + video surfaces + structs

| Set | Oracle | Emitted | Witness | Notes |
|-----|--------|---------|---------|-------|
| DXGI interfaces | 43 | 43 | factory/adapter/WARP/swapchain driven live | DXGI SDK headers; own methods = vtbl diff vs the base |
| DXGI vtbl rows (incl. inherited) | 816 | -- | -- | absolute slots in `dxgi_calls.c` |
| DXGI own methods | 163 | **163 wrappers** | object/adapters/swapchain paths live | **0 unmapped** |
| DXGI enums | 246 values | **246 consts** | `DXGI_FORMAT_B8G8R8A8_UNORM` etc. checked | `dxgi_consts_1` |
| DXGI free functions | 6 | **6 wrappers** | `CreateDXGIFactory2` via the bridge; generated wrappers resolve lazily | `xd12_resolve_dxgi` |
| Video interfaces | 30 | 30 | `ID3D12VideoDevice` QI + video decode command list live | `d3d12video.h` @ the clone |
| Video vtbl rows (incl. inherited) | 550 | -- | -- | absolute slots in `video_calls.c` |
| Video own methods | 200 | **190 wrappers + 10 typed shims** | VIDEO_DECODE chain + generated `Close` live | **0 unmapped** |
| Video enums | 661 values | **661 consts** | generated | `video_consts_1..3` |
| Struct sizes | 434 (D3D12+DXGI+video) | **434 consts** | 16-struct oracle-vs-build sizeof cross-check | `D3D12_SIZEOF_*` / `DXGI_SIZEOF_*` |
| Struct member offsets | 1804 | **1804 consts** | live field reads through `D3D12_OFF_*`/`DXGI_OFF_*` | 2238 consts total in `struct_meta_1..5` |

Live witness (2026-10-12, x2 on the RTX 3070 Ti, v0.64.4):

```
[PASS] surface: d3d12_device_get_node_count = 1
[PASS] surface: CreateCommandQueue hr=0 (queue live)
[PASS] struct: CommandQueue::GetDesc sret (type=0 priority=100)
[PASS] surface: queue Release -> refcount 0
[PASS] struct: CreateCommittedResource(buffer 256B) hr=0
[PASS] struct: Resource::GetDesc sret (dim=1 width=256 mips=1)
[PASS] struct: GetResourceAllocationInfo sret (size=65536 align=65536)
[PASS] struct: GetCustomHeapProperties sret (heap_type=4)
[PASS] struct: oracle-vs-build sizeof cross-check (16 closure structs)
[PASS] surface: D3D12SerializeRootSignature wrapper hr=0
[PASS] surface: root signature serialized (size=88 magic=0x1403377099057813572)
[PASS] dxgi: live IDXGIFactory2 pointer
[PASS] dxgi: EnumAdapters1 count=3
[PASS] dxgi: Adapter1::GetDesc1 vendor=4318 (decimal; 0x10DE NVIDIA)
[PASS] dxgi: EnumWarpAdapter live
[PASS] dxgi: WARP vendor=5140 (expect 5140 == 0x1414)
[PASS] dxgi: D3D12CreateDevice(WARP) ok (warp_status=0)
[PASS] dxgi: BGRA8/FIFO swapchain (swap=0 buffer=0 present=0 640x480)
[PASS] video: ID3D12VideoDevice QI ok
[PASS] video: CreateCommandList(VIDEO_DECODE) hr=0
[PASS] video: VideoDecodeCommandList::Close hr=0
```

Skip ledger: 97 unparsed struct shapes (anonymous unions / bitfields /
function-pointer members) are documented in
`docs/struct_meta_manifest.json::struct_skips`; all method skips are bound
(19 + 3 + 0 + 10).  The by-value `D3D12_NODE_ID` marshaling
(`GetNodeIndex`/`GetEntrypointIndex`) is emitted but not live-witnessed
(needs a work-graph state object); layout is oracle-verified.

Pointer-edged flows run through C return values or bridge-owned state
(B-24: XIOM out-slot reads after a C write are not reliable -- use
byte-indexed reads; repro in `docs/repro/bindings-pilot/ptr-read-stale/`).
B-23: the `null` literal crosses to C as garbage; use `dx12_null_ptr()`.

Next: promotion readiness (policy sec. 7).
