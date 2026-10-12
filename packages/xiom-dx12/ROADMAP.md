# xiom.dx12 -- Roadmap

**Version**: v0.3.0 | **Compiler**: xiom v0.64.4 | **Last updated**: 2026-10-12

## Current state

| Criterion | Status |
|-----------|--------|
| Runtime loader (no link dependency) | Done -- `d3d12.dll` via `LoadLibraryA`/`GetProcAddress` |
| COM/vtable ABI pinned from DirectX-Headers | Done -- 0.1.0 (IIDs + slots in `SPEC.md` sec. 2) |
| Device + allocator roundtrip probe | Done -- 0.1.0 (5/5 x2 on the RTX 3070 Ti) |
| SKIP classification (absent / no adapter / ABI) | Done |
| Full `d3d12.h` surface (interfaces + free fns + enums) | Done -- 0.2.0 (358 wrappers + 1162 consts + 9 free fns) |
| Coverage manifest (oracle == bound == resolved) | Done -- `docs/COVERAGE.md` |
| Struct metadata (sret/by-value normal forms + offsets) | Done -- 0.3.0 (19 typed shims + 1103 meta consts; 55 documented shapes) |
| DXGI factory/adapter/swapchain | 0.3.0 (wave b) |
| WARP fallback adapter | 0.3.0 (wave b) |
| Command recording (queue/list/allocator + fences) | 0.4.0 |

## Phase 3 (0.3.0 goals)

1. Struct metadata: sret/by-value normal forms for the struct-by-value
   methods + offset tables (vulkan struct-meta style).  **DONE** --
   `src/d3d12_structs.c` (19 typed shims; x64 member-return convention
   pinned in `SPEC.md`), `src/struct_meta_1..3.xi` (240 sizes + 863
   offsets from a clang `sizeof`/`offsetof` dump), oracle-vs-build sizeof
   probes in-suite.
2. DXGI (`dxgi.dll`): `CreateDXGIFactory2`, adapter enumeration, WARP,
   BGRA8/FIFO swapchain behind the same loader + SKIP rules.
3. WARP device fallback so adapter-less CI hosts reach a real device stage.
4. `d3d12video.h` slice; then promotion (policy sec. 7).
