# xiom.vulkan -- Roadmap

**Version**: v0.7.0 | **Compiler**: xiom v0.65.4 | **Last updated**: 2026-10-31

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no SDK, no link dependency) | Done -- `vkGetInstanceProcAddr`/`vkGetDeviceProcAddr` seam |
| Header-free bridge (minimal ABI + opaque buffers) | Done |
| G2 pin (soname + header hash + entry points + struct layouts) | Done -- `SPEC.md` Â§2 |
| Capability probe (extensions/layers/device) | Done -- 10/10 x2 |
| SKIP classification (absent / no ICD / ABI) | Done |
| Instance with surface extensions | Done (0.3.0) |
| Surface + swapchain (Win32) | Done (0.4.0) -- 3 clear+present round trips |
| Queues + command buffers + frames | Done (0.3.0/0.4.0) |
| Shaders (SPIR-V loading) | Done (0.5.0) -- glslc + embedded `.inc` |
| Render pipeline (clear, draw, present, readback) | Done (0.5.0) -- 22/22 x2 |
| Mini-RHI tier (sync, buffers, surface/resize, compute, indirect, labels) | Done (0.7.0) -- 36/36 x2; texture/depth/caller-SPIR-V raw recipe in docs/MINI-RHI.md |\n| Capture copy + query readback (C07/B05) | Done (0.6.1) -- stable full-frame checksum + timestamp/occlusion readback; 24/24 x2 |
| Compute pipelines | Phase 4 |
| Buffers/images + memory allocator | Phase 4 (readback buffer exists) |

## Phase 4 (next touches, over this seam)

1. Compute pipeline + storage buffers (the first GPU-compute proof).
2. Descriptors + textures (combined image samplers); stb image upload.
3. Depth/stencil attachment + a rotating cube example.
4. Per-frame synchronization (fences/frames-in-flight) instead of wait-idle.
5. Instance extension/layer enablement by request (debug-utils when present).
