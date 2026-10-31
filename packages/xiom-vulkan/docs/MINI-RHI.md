# Mini-RHI tier (0.7.0)

Closes the mini-RHI backlog: `REL-20261010-1834-engine-2`,
`REL-20261011-2015-engine`, `REL-20261012-2012-engine-2`,
`REL-20261016-1341-engine-3`.  Every probe below is in the conformance
suite; the texture/depth/caller-SPIR-V path is pinned as a raw sequence
(the engine already exercises depth/lit/indexed draws on that seam).

## Delivered probes (36/36 x2 on v0.65.4, RTX 3070 Ti)

| Ask | API | Evidence |
|-----|-----|----------|
| Per-frame sync + recording (2015 #1) | `vulkan_frame_sync_probe(frames)` | 2 cmd buffers + 2 fences + acquire/render semaphores, no queue idle in the loop; 3 acquire/submit/present frames |
| Host-visible buffers (2015 #2) | `vulkan_buffer_probe()` | 3 vertices x stride 48 uploaded and read back (144 B, checksum) |
| Caller SPIR-V + depth + texture (2015 #3/#4/#5) | raw sequence below | engine-proven; published recipe + offsets |
| SDL3/engine-owned window surface + resize (2015 #6) | `vulkan_surface_probe(w,h,frames)`; `xw_window_from_hwnd` | external HWND, 640x480, clear/present, recreate 784x561 |
| FIFO + IMMEDIATE (2015 #7) | same probe | selects IMMEDIATE when offered (mode 0), else FIFO (2) |
| Compute + dispatch (2012 #1) | `vulkan_compute_probe()` | storage buffer + descriptor + `vkCmdDispatch(4,1,1)`, `v[i]=v[i]*3+1` x256 (first 1, last 766) |
| Indirect draws (2012 #2) | `vulkan_indirect_probe(frames)` | index buffer + `VkDrawIndexedIndirectCommand`, `vkCmdDrawIndexedIndirect`, center green |
| Timestamp/occlusion queries (2012 #3) | `VulkanTriangle` capture/query fields | 3072 ns @ 1 ns/tick, 24576 occlusion samples |
| Debug labels/regions (2012 #4) | `vulkan_labels_probe()` | `VK_EXT_debug_utils` enabled when advertised; begin/end label submitted |

## Raw texture + depth + caller-SPIR-V sequence

This is what the engine does on its own command buffer; offsets come from
the pinned 1.4.350 headers (`src/struct_meta_*.xi`).

1. **Caller SPIR-V.** `vkCreateShaderModule` from the engine's `glslc`
   output (vertex: positions from `gl_VertexIndex` or a stride-48 vertex
   buffer; fragment: `texture(tex, uv) * tint`). Pipeline layout:
   descriptor set 0 binding 0 (`COMBINED_IMAGE_SAMPLER`, stage 0x10) and a
   push range `stageFlags=0x11, offset=0, size=20` for
   `{ vec4 color; float z; }`.
2. **Texture.** `VK_FORMAT_R8G8B8A8_UNORM` (37), usage
   `SAMPLED|TRANSFER_DST` (0x6), `VK_IMAGE_TILING_OPTIMAL` (0). Clear/upload,
   then barrier to `SHADER_READ_ONLY_OPTIMAL` (5). Sampler: NEAREST,
   CLAMP_TO_EDGE; descriptor image info `{sampler, view, layout=5}`.
3. **Depth.** `VK_FORMAT_D32_SFLOAT` (126), usage
   `DEPTH_STENCIL_ATTACHMENT` (0x20), `TILING_OPTIMAL`, view aspect
   `DEPTH` (0x2). Render pass attachment: `loadOp=CLEAR`,
   `clearDepth=1.0`, `finalLayout=DEPTH_STENCIL_ATTACHMENT_OPTIMAL` (3).
   Pipeline depth state: `depthTestEnable=1`, `depthWriteEnable=1`,
   `depthCompareOp=LESS` (1).
4. **Draw.** Color attachment final layout `TRANSFER_SRC_OPTIMAL` (6);
   `vkCmdWriteTimestamp`/labels optional around the draw. Push
   `{green, z=0.25}` and draw the near triangle, then `{red, z=0.75}` and
   draw the far triangle; `LESS` keeps the near green at the center.
   Barrier color `COLOR_ATTACHMENT_WRITE -> TRANSFER_READ`, copy the image
   to a host-visible `TRANSFER_DST` buffer, barrier to `PRESENT_SRC_KHR`,
   present.
5. **Present mode.** Enumerate
   `vkGetPhysicalDeviceSurfacePresentModesKHR`; use `IMMEDIATE` (0) when
   offered, else `FIFO` (2). Resize: wait idle, destroy/recreate the
   swapchain with the new extent (`xw_recreate_swapchain`).

## Engine-owned window

`sdl3_window_native_handle(win)` returns the Win32 HWND (kind 1) from the
0.22.0 SDL3 surface tier.  Pass `handle` to `xw_window_from_hwnd(hwnd, w,
h)` before `xw_surface()`/`xw_swapchain()`, or create the surface in the
engine and hand the `VkSurfaceKHR` to the swapchain path.  The engine keeps
window ownership; `xw_destroy` never destroys an external HWND.

## Notes

- The reference `xw_texture_depth_probe` in `src/vk_rhi.c` is experimental
  (not exposed in the public API and not in the suite); the raw sequence
  above is the supported path.
- Compute uses `mini_comp.comp` (`src/shaders/`), compiled with
  `glslc` and embedded via `tools/embed_spv.py`.
- All probes SKIP cleanly when `vulkan-1.dll` is absent.
