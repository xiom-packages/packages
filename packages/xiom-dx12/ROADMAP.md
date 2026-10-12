# xiom.dx12 -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.4 | **Last updated**: 2026-10-12

## Current state

| Criterion | Status |
|-----------|--------|
| Runtime loader (no link dependency) | Done -- `d3d12.dll` via `LoadLibraryA`/`GetProcAddress` |
| COM/vtable ABI pinned from DirectX-Headers | Done -- 0.1.0 (IIDs + slots in `SPEC.md` sec. 2) |
| Device + allocator roundtrip probe | Done -- 0.1.0 (5/5 x2 on the RTX 3070 Ti) |
| SKIP classification (absent / no adapter / ABI) | Done |
| Full `d3d12.h` surface (interfaces + free fns + enums) | Done -- 0.2.0 (355 wrappers + 1162 consts + 9 free fns; 12/12 x2) |
| Coverage manifest (oracle == bound == resolved) | Done -- `docs/COVERAGE.md` (slice 1) |
| Struct metadata (sret/by-value normal forms + offsets) | 0.3.0 |
| DXGI factory/adapter/swapchain | 0.3.0 |
| WARP fallback adapter | 0.3.0 |
| Command recording (queue/list/allocator + fences) | 0.4.0 |

## Phase 3 (0.3.0 goals)

1. Struct metadata: sret/by-value normal forms for the 22 skipped shapes +
   offset tables (vulkan struct-meta style) so `GetDesc`-family methods bind.
2. DXGI (`dxgi.dll`): `CreateDXGIFactory2`, adapter enumeration, WARP,
   BGRA8/FIFO swapchain behind the same loader + SKIP rules.
3. WARP device fallback so adapter-less CI hosts reach a real device stage.
4. `d3d12video.h` slice; then promotion (policy sec. 7).
