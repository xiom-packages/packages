# COVERAGE -- xiom.dx12 (slice 1: the full `d3d12.h` core surface)

Oracle: `microsoft/DirectX-Headers` @ `461ef513` --
`include/directx/d3d12.h` (SHA256 `AFA193D3...`).  Generator:
`tools/gen_dx12.py` (deterministic, Python stdlib only).

| Set | Oracle | Emitted | Witness | Notes |
|-----|--------|---------|---------|-------|
| Interfaces | 90 | 90 | -- | all `MIDL_INTERFACE` blocks parsed; own methods = vtbl diff vs the base |
| Vtable rows (incl. inherited) | 2476 | -- | -- | absolute slot indices preserved in the shims |
| Own methods | 377 | **355 wrappers** | device/object/queue paths exercised live | 22 skips: struct-by-value (sret > 8B or by-value params) -- struct-metadata wave |
| Enums | 1162 values | **1162 consts** | sanity-checked (`D3D12_FILL_MODE_SOLID`, `D3D12_HEAP_TYPE_*`, `D3D12_RESOURCE_STATE_COMMON`) | expression-evaluated |
| Free functions | 9 | **9 wrappers** | serialized a 1-root-constant signature | lazy resolve via `xd12_resolve` |

Live witness (2026-10-12, x2 on the RTX 3070 Ti, v0.64.4):

```
[PASS] surface: d3d12_device_get_node_count = 1
[PASS] surface: CreateCommandQueue hr=0 (queue live)
[PASS] surface: queue Release -> refcount 0
[PASS] surface: D3D12SerializeRootSignature wrapper hr=0
[PASS] surface: root signature serialized (size=88 magic=0x1403377099057813572)
```

Skip ledger (`docs/gen_manifest.json`): 22 command skips, all
struct-by-value shapes (`GetDesc`-family sret, `D3D12_NODE_ID` by value,
etc.); 0 unmapped types remain.

Next slices: DXGI (`dxgi.dll`: factory/adapters/WARP/swapchain),
struct metadata (offsets + sret/by-value normal forms), `d3d12video.h`,
then promotion (policy sec. 7).
