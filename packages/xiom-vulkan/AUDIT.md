# AUDIT: xiom.vulkan

## Status (2026-10-31)

Dynamic-loader implementation at **0.7.0**: capability probe + engine RHI
bring-up + WSI + render pipeline (clear, draw a triangle, present with
readback proof) + C07 stable capture-copy + B05 timestamp/occlusion query
readback.  (0.6.0 is the published SDK100 raw-surface cut and is immutable;
0.6.1 re-cuts the capture/query helper.)

| Item | State |
|------|-------|
| Compiler | xiom v0.65.4 |
| Pin | soname `vulkan-1.dll` + tag `vulkan-sdk-1.4.350.0` `vulkan_core.h` hash + entry-point set + struct/constant layouts (`SPEC.md` Â§2) |
| Link model | none at build time; runtime `LoadLibraryA` + `vkGetInstanceProcAddr` / `vkGetDeviceProcAddr`; **no Vulkan headers included** (minimal ABI declared locally, opaque receive buffers) |
| Build | `port.args.json`: `--c-source vk_probe.c`, `--c-source vk_rhi.c`, `--link user32` (hidden WSI window) |
| Shaders | `src/shaders/tri.vert`/`tri.frag` -> glslc -> `tools/embed_spv.py` -> committed `src/tri_*_spv.inc` (regenerable) |
| FFI confinement | all `unsafe`/`extern` in the root module `xiom.vulkan` (G5); the bridges are plain C |
| Suite | `tests/test_conformance.xi`, 36 checks (SKIP-classified when absent) |
| Runs | **PASS 36/36 x2** via `scripts/port.ps1` on 2026-10-31 (loader 1.4.350, v0.65.4, RTX 3070 Ti, ~25 s/run; capture crc 335003077 stable, 3072 ns @ 1 ns/tick, 24576 occlusion samples) |

## Design notes

- **Scalar-only boundary** (B-11/B-12 discipline): every value crossing into
  XIOM is an int/string; the only buffers are XIOM-owned slots in other
  packages -- here the bridge keeps all Vulkan structs and the readback
  buffer on the C side and reports pixels as packed ints.
- **Device-level entry points resolve via `vkGetDeviceProcAddr`** (the 1.4.x
  loader VUID-fast-fails a device through `vkGetInstanceProcAddr`).
- **WSI**: hidden `WS_POPUP` window (never shown), FIFO swapchain,
  B8G8R8A8 preferred, min+1 images; acquire/clear/present with binary
  semaphores. 0.5.0 corrects the 0.4.0 layout constant
  `XW_LAYOUT_TRANSFER_DST_OPTIMAL` (6 -> 7; 6 is TRANSFER_SRC in the 1.4
  header) -- covered by the continuing clear+present checks.
- **Render pipeline**: single-attachment render pass (loadOp CLEAR,
  finalLayout TRANSFER_SRC), pipeline from embedded SPIR-V (positions from
  `gl_VertexIndex`, no vertex buffers), `vkCmdDraw(3)`, then
  `vkCmdCopyImageToBuffer` readback before the present barrier. The suite
  asserts the center pixel is the green triangle and the bottom-left sample
  is the clear color -- a pixel-level proof of "clears, draws a triangle,
  presents" (Vulkan NDC y inversion noted at the sample site).
- **Capture/query (0.6.1)**: the existing triangle frame now carries a
  2-query TIMESTAMP pool + a 1-query OCCLUSION pool; the draw brackets
  `vkCmdWriteTimestamp` (COLOR_ATTACHMENT_OUTPUT) and
  `vkCmdBeginQuery`/`vkCmdEndQuery`, then `vkGetQueryPoolResults`
  (`64_BIT|WAIT`) after the queue wait. The full `extent_w*extent_h*4`
  readback is hashed with FNV-1a and compared across frames (C07 stable
  copy); `VulkanTriangle` exposes bytes/crc/stable, timestamp begin/end,
  `timestamp_period_ns`, `duration_ns` and `occlusion_samples` (B05).
  `docs/CAPTURE-QUERY.md` pins the raw sequence for engine-owned command
  buffers. Timestamp/occlusion are best-effort on devices without support
  (`query_ok=false`); the pinned host reports both live.
- Out-of-scope by design (later phases): compute pipelines, descriptors,
  depth/stencil, textures, per-frame synchronization (0.6.1 waits idle),
  instance extension/layer enablement beyond the surface pair.

## Known limitations

- Windows loader name only (`vulkan-1.dll`); Windows x64 first.
- Instance creation requests API 1.0 for compatibility; device apiVersion is
  reported from `VkPhysicalDeviceProperties`.
- The no-ICD SKIP path is code-reviewed, not force-tested (this host has a
  driver); the bogus-soname SKIP classification runs in every suite run.
- Triangle sample points are fixed fractions of the 320x240 surface
  (center vs bottom-left quadrant); swapchain extent changes do not affect
  the classification thresholds.
