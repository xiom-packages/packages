# xiom.dx12 -- Roadmap

**Version**: v0.1.0 | **Compiler**: xiom v0.64.4 | **Last updated**: 2026-10-12

## Current state

| Criterion | Status |
|-----------|--------|
| Runtime loader (no link dependency) | Done -- `d3d12.dll` via `LoadLibraryA`/`GetProcAddress` |
| COM/vtable ABI pinned from DirectX-Headers | Done -- 0.1.0 (IIDs + slots in `SPEC.md` sec. 2) |
| Device + allocator roundtrip probe | Done -- 0.1.0 (5/5 x2 on the RTX 3070 Ti) |
| SKIP classification (absent / no adapter / ABI) | Done |
| Full generated surface (all `ID3D12*` + free fns + enum/struct meta) | 0.2.0 |
| DXGI factory/adapter/swapchain | 0.2.0 |
| WARP fallback adapter | 0.2.0 |
| Coverage manifest (oracle == bound == resolved) | 0.2.0 |
| Command recording (queue/list/allocator + fences) | 0.3.0 |

## Phase 2 (0.2.0 goals)

1. Generator `tools/gen_dx12.py` from the pinned headers: interface/vtable
   tables, free-function wrappers, enum/struct metadata (offset tables like
   the vulkan struct-meta) + `docs/COVERAGE.md`.
2. DXGI: `CreateDXGIFactory2`, adapter enumeration, WARP, swapchain creation
   (BGRA8/FIFO) behind the same loader + SKIP rules.
3. WARP device fallback so adapter-less CI hosts reach a real device stage.
