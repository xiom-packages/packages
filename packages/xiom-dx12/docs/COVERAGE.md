# COVERAGE -- xiom.dx12 (slice 2: struct metadata + full `d3d12.h` core surface)

Oracle: `microsoft/DirectX-Headers` @ `461ef513` --
`include/directx/d3d12.h` (SHA256 `AFA193D3...`), with `dxgicommon.h` /
`dxgiformat.h` for member types.  Generators: `tools/gen_dx12.py` (surface +
typed shims; deterministic, Python stdlib only) and
`tools/gen_dx12_struct_meta.py` (+ `tools/struct_dump.cpp` compiled with
clang against the pinned headers -> `docs/struct_dump.txt`).

| Set | Oracle | Emitted | Witness | Notes |
|-----|--------|---------|---------|-------|
| Interfaces | 90 | 90 | -- | all `MIDL_INTERFACE` blocks parsed; own methods = vtbl diff vs the base |
| Vtable rows (incl. inherited) | 2476 | -- | -- | absolute slot indices preserved in the shims |
| Own methods | 377 | **358 wrappers** | device/object/queue paths exercised live | 355 standard + 3 callback-param (`D3D12*Func` -> raw address); **0 unmapped** |
| Typed shims (struct-by-value normal forms) | 19 | **19 shims** | queue/resource `GetDesc` sret, `GetResourceAllocationInfo`, `GetCustomHeapProperties` live | sret via caller-owned slot; by-value `D3D12_NODE_ID` params via owned slot pointer |
| Enums | 1162 values | **1162 consts** | sanity-checked (`D3D12_FILL_MODE_SOLID`, `D3D12_HEAP_TYPE_*`, `D3D12_RESOURCE_STATE_COMMON`) | expression-evaluated |
| Free functions | 9 | **9 wrappers** | serialized a 1-root-constant signature | lazy resolve via `xd12_resolve` |
| Struct sizes | 240 | **240 consts** | 16-struct oracle-vs-build sizeof cross-check | `D3D12_SIZEOF_*` in `struct_meta_1..3` |
| Struct member offsets | 863 | **863 consts** | live field reads through `D3D12_OFF_*` (width/mips/layout/priority/...) | `struct_meta_1..3`; 1103 consts total |

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
```

Skip ledger: 55 unparsed struct shapes (anonymous unions / bitfields /
function-pointer members) are documented in
`docs/struct_meta_manifest.json::struct_skips`; the 22 struct/callback
method skips of 0.2.0 are all bound (19 typed + 3 callback-param).  The
by-value `D3D12_NODE_ID` marshaling (`GetNodeIndex`/`GetEntrypointIndex`)
is emitted but not live-witnessed (needs a work-graph state object);
layout is oracle-verified.

Next slices: DXGI (`dxgi.dll`: factory/adapters/WARP/swapchain),
`d3d12video.h`, then promotion (policy sec. 7).
