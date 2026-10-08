# xiom.vulkan -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-08

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no SDK, no link dependency) | Done -- `vkGetInstanceProcAddr` seam |
| Header-free bridge (minimal ABI + opaque buffers) | Done |
| G2 pin (soname + header hash + entry points) | Done -- `SPEC.md` §2 |
| Capability probe (extensions/layers/device) | Done -- 10/10 x2 |
| SKIP classification (absent / no ICD / ABI) | Done |
| Instance with extensions/debug layers | Phase 3 |
| Surface + swapchain (Win32) | Phase 3 |
| Queues + command buffers + frames | Phase 3 |
| Buffers/images/memory | Phase 3 |
| Shaders (SPIR-V loading) | Phase 3 |
| Compute + render pipelines | Phase 3 |

## Phase 3 (next touches, over this seam)

1. Instance extensions: enable a caller-provided list (surface, debug utils)
   with validation of availability; report enabled vs available.
2. Win32 surface + swapchain: `VkWin32SurfaceCreateInfoKHR`/
   `vkCreateWin32SurfaceKHR` and `vkCreateSwapchainKHR` with X11-free
   Windows-only paths first.
3. Device selection: pick a queue-family for graphics/present; expose
   queue-family properties (count, flags) in the probe.
4. Memory + buffers: host-visible staging buffers as the first allocator-free
   step; images/textures after.
5. Shaders: load SPIR-V from `Vec[UInt32]`, create shader modules, first
   triangle pipeline in a hidden-window example.
6. Rebuild the pre-pilot engine capabilities deliberately (its bridge is in
   git history): choose what to resurrect over the loader seam instead of
   restoring a monolithic C engine.
