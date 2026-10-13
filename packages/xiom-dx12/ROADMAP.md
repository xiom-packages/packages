# xiom.dx12 -- Roadmap

**Version**: v0.4.0 | **Compiler**: xiom v0.64.4 | **Last updated**: 2026-10-13

## Current state

| Criterion | Status |
|-----------|--------|
| Runtime loader (no link dependency) | Done -- `d3d12.dll` via `LoadLibraryA`/`GetProcAddress` |
| COM/vtable ABI pinned from DirectX-Headers | Done -- 0.1.0 (IIDs + slots in `SPEC.md` sec. 2) |
| Device + allocator roundtrip probe | Done -- 0.1.0 (5/5 x2 on the RTX 3070 Ti) |
| SKIP classification (absent / no adapter / ABI) | Done |
| Full `d3d12.h` surface (interfaces + free fns + enums) | Done -- 0.2.0 (358 wrappers + 1162 consts + 9 free fns) |
| Coverage manifest (oracle == bound == resolved) | Done -- `docs/COVERAGE.md` |
| Struct metadata (sret/by-value normal forms + offsets) | Done -- 0.3.0 (29 typed shims + 2238 meta consts; 97 documented shapes) |
| DXGI factory/adapter/swapchain | Done -- 0.3.0 (43 interfaces / 163 wrappers / 6 free fns / 246 consts; live factory + 3 adapters + 640x480 BGRA8/FIFO swapchain) |
| WARP fallback adapter | Done -- 0.3.0 (`EnumWarpAdapter` + `D3D12CreateDevice(WARP)` ok) |
| `d3d12video.h` slice | Done -- 0.3.0 (30 interfaces / 190 wrappers / 661 consts / 10 typed shims; QI + VIDEO_DECODE chain live) |
| Promotion to `stable` | Done -- 0.3.1 (2026-10-13; `SPEC.md` sec. 7 G1-G7 gate; publish rides the standard batch) |
| Command recording (queue/list/allocator + fences) | Done -- 0.4.0 (allocator `Reset`, list create/`Close`, `dx12_execute_one`, fence signal + `dx12_fence_wait`; 42/42 x2; COM object params typed `Int` -- B-25) |
| Recording conveniences (barrier helpers, bundles, command signatures) | next |

## Phase 3 (0.3.0 goals)

1. Struct metadata: sret/by-value normal forms for the struct-by-value
   methods + offset tables (vulkan struct-meta style).  **DONE** --
   `src/d3d12_structs.c` (19 typed shims; x64 member-return convention
   pinned in `SPEC.md`), `src/struct_meta_1..3.xi` (272 sizes + 1036
   offsets from a clang `sizeof`/`offsetof` dump), oracle-vs-build sizeof
   probes in-suite.
2. DXGI (`dxgi.dll`): `CreateDXGIFactory2`, adapter enumeration, WARP,
   BGRA8/FIFO swapchain behind the same loader + SKIP rules.  **DONE** --
   `tools/gen_dx12.py` DXGI pass (163 wrappers/246 consts/6 free fns),
   `src/dxgi_probe.c` (factory/adapters/WARP/hidden-window swapchain),
   module `xiom.dx12.dxgi`, suite witnesses live.
3. WARP device fallback so adapter-less CI hosts reach a real device stage.
   **DONE** -- `dxgi_warp_device_probe()` creates + releases a D3D12 device
   on the WARP adapter (live-verified).
4. `d3d12video.h` slice; then promotion (policy sec. 7).  **DONE** --
   `src/video_probe.c` + module `xiom.dx12.video`, 30 interfaces / 190
   wrappers / 661 consts / 10 typed shims; QI + VIDEO_DECODE command-list
   chain live.  Promotion **DONE** at 0.3.1 (2026-10-13): G1-G7 gate
   green (35/35 x2, trap-14 clean, contracts inventoried, workarounds
   accepted with expiry; no dependents).

## Phase 4 (0.4.0)

1. Command recording: allocator + list lifecycle, submission
   (`ExecuteCommandLists`), fence signal/wait.  **DONE** -- 0.4.0:
   `src/recording.xi` (`dx12_execute_one`), root `dx12_fence_wait`
   (bridge: Win32 event + `WaitForSingleObject`), suite 42/42 x2
   (execute + signal + wait round-trip live).  The wave also surfaced
   **B-25** (`Int as *UInt8` not value-preserving): COM object params are
   now typed `Int` in the generated surface; repro + finding filed.
2. Next candidates: resource-barrier helpers, bundle recording
   (`D3D12_COMMAND_LIST_TYPE_BUNDLE`), command signatures, descriptor-heap
   conveniences -- only on consumer ask or the engine's DX12 track.
