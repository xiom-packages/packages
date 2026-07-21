# XIOM Vulkan Bridge -- Comprehensive Audit Report (Re-Audit)

**Entry file:** `ecosystem\xiom-vulkan\bridge\xiom_vk_bridge.c` (umbrella, 34 lines -- includes 29 modules)
**Total bridge code:** ~6,939 lines across 29 `.c` files + headers
**Audit date:** 2026-07-18 (re-scan; supersedes previous audit of the 3,984-line monolith)
**Vulkan API version:** **1.3** (`VK_API_VERSION_1_3` in both instance paths), with compile-gated 1.1 / 1.2 / 1.3 / 1.4 core entry points
**Exported ABI:** 368 `xvk_*` functions (~280 in the raw binding layer)
**Vulkan entry points invoked:** 154 unique direct `vk*` calls + ~90 resolved at runtime via `vkGetInstanceProcAddr` / `vkGetDeviceProcAddr`

---

## 0. Architectural Change Since Last Audit

The monolithic bridge was split into **two layers**:

| Layer | Files | Style |
|---|---|---|
| **Legacy app layer** | `xvk_app.c`, `xvk_frame.c`, `xvk_legacy.c`, `xvk_offscreen.c`, `xvk_instance.c`, `xvk_swapchain.c`, `xvk_pipeline.c`, `xvk_renderpass.c`, `xvk_descriptor.c`, `xvk_buffer.c`, `xvk_command.c`, `xvk_query.c`, `xvk_util.c`, `xvk_math.c` | Simplified handle-based API (magic-validated opaque handles, int-enum mapping). Same behaviour as previous audit, plus upgrades noted below. |
| **Raw binding layer** | `xvk_structs.c` + 14 `xvk_bind_*.c` modules | **1:1 Vulkan bindings.** XIOM builds real Vulkan structs byte-by-byte via the marshalling layer (`xvk_alloc`, `xvk_write_u32/u64/f32/str/array`, `xvk_set_sType/pNext`) and passes raw pointers/handles. The C side enforces `sType` and calls the real VK function. ABI verified with `_Static_assert` offset checks. |

Consequence: **anything expressible through Vulkan create-info structs is now reachable from XIOM** (MSAA pipelines, tessellation/geometry stages, specialization constants, cube/3D/array images, pNext feature chains, arbitrary instance/device extensions), because the raw layer does not interpret the structs -- it forwards them.

Legacy upgrades since last audit:
- API version raised 1.0 → 1.3 (`xvk_instance.c:19`, `xvk_bind_instance.c:56`)
- Device features now enabled: `samplerAnisotropy`, `fillModeNonSolid`, `wideLines` (`xvk_instance.c:144-147`)
- Simplified query-pool API added (`xvk_query.c`)
- Legacy recording helpers renamed `xvk_cmd_*` → `xvk_app_cmd_*` to free the `xvk_cmd_*` namespace for raw bindings

---

## Summary Scorecard

| # | Area | Prev | Now | Status |
|---|------|------|-----|--------|
| 1 | Instance / Device | 100% | 100% | FULL (both layers; raw layer accepts arbitrary layers/extensions/pNext) |
| 2 | Swapchain | 100% | 100% | FULL+ (oldSwapchain recreation, surface caps2, display KHR, headless, HDR, FSE) |
| 3 | Render Pass / Framebuffer | 95% | 100% | FULL (renderpass2, multi-subpass, dynamic rendering) |
| 4 | Pipelines (graphics/compute) | 95% | 98% | FULL (caller-built create infos; pipeline cache create -- no serialize) |
| 5 | Shader Modules | 100% | 100% | FULL (+ VK_EXT_shader_object) |
| 6 | Command Buffers | 85% | 97% | FULL (secondary, indirect, copies, clears, resolve; 1 gap: plain `vkCmdDrawIndexedIndirect`) |
| 7 | Descriptor Sets | 90% | 100% | FULL (copies, templates, push descriptors, dynamic offsets) |
| 8 | Vertex / Index Buffers | 90% | 100% | FULL (+ buffer views, buffer device address) |
| 9 | Images / Views / Samplers | 85% | 98% | FULL (blit → mipmap gen possible; arbitrary create infos via raw layer) |
| 10 | Synchronization | 80% | 95% | FULL (events, sync2, timeline semaphores; missing host-side event set/reset/status) |
| 11 | Memory | 85% | 97% | FULL (flush/invalidate, arbitrary bind offsets → suballocation possible) |
| 12 | Push Constants | 90% | 100% | FULL (+ `vkCmdPushConstants2`, 1.4-gated) |
| 13 | **Dynamic State** | **5%** | **100%** | **FULL** -- all 9 core-1.0 setters + extended dynamic state 1/2/3 |
| 14 | Query Pools | 0% | 100% | FULL (occlusion / timestamp / pipeline-stats, host + cmd copy results) |
| 15 | Ray Tracing | 0% | 95% | FULL bindings (KHR AS, KHR RT pipeline, NV legacy, EXT micromap; no deferred-op create) |
| 16 | Extensions (misc) | ~5% | ~90% | Debug utils, mesh shader, conditional rendering, transform feedback, FSR, video, etc. |

**Overall coverage: ~94%** of the practical Vulkan 1.0-1.3 surface (was ~87%).
**All paths are real Vulkan calls.** The only "stubs" are deliberate compile-time gates that report an error when built against pre-1.1/1.2/1.3/1.4 headers, and micromap stubs for SDK < 1.3.230.

---

## 1. Instance / Device

**Legacy** (`xvk_instance.c`): `vkCreateInstance` (1.3, GLFW extensions, fail-soft `VK_LAYER_KHRONOS_validation` via `XVK_VALIDATION=1`), `vkEnumeratePhysicalDevices`, `vkGetPhysicalDeviceProperties`, discrete-GPU preference, `vkCreateDevice` (swapchain ext + 3 features), `vkGetDeviceQueue`, `glfwCreateWindowSurface`.

**Raw** (`xvk_bind_instance.c`, `xvk_bind_device.c`): `xvk_create_instance` (caller-supplied layer/extension name arrays), `xvk_destroy_instance`, `xvk_enumerate_physical_devices`, `xvk_get_physical_device_properties`, `xvk_create_device` (**caller-built `VkDeviceQueueCreateInfo[]`, extension list, `VkPhysicalDeviceFeatures`, and full `pNext` chain** -- any 1.1+/extension feature struct can be chained), `xvk_get_device_queue`, `xvk_device_wait_idle`. Struct offsets ABI-checked via `XVK_STATIC_ASSERT`.

Missing: `vkGetPhysicalDeviceFeatures(2)`, `vkGetPhysicalDeviceProperties2`, `vkGetPhysicalDeviceFormatProperties2`, `vkGetPhysicalDeviceImageFormatProperties`, `vkEnumerateInstanceExtensionProperties`, `vkEnumerateDeviceExtensionProperties`, `vkEnumerateInstanceVersion`, `vkQueueWaitIdle`. Feature chains can be *enabled* blind but not *queried* first.

**Status: FULL** (query side of physical-device introspection is the gap).

---

## 2. Swapchain / Surface / Present

**Legacy** (`xvk_swapchain.c`, `xvk_frame.c`): full swapchain lifecycle -- `vkCreateSwapchainKHR`, `vkGetSwapchainImagesKHR`, per-image views, `vkAcquireNextImageKHR`, `vkQueuePresentKHR`, out-of-date/suboptimal recreation, zero-size-window guard, BGRA8+SRGB pick, MAILBOX preferred / FIFO fallback.

**Raw** (`xvk_bind_swapchain.c`, 526 lines): `xvk_create_swapchain_khr`, `xvk_create_swapchain2_khr` (**enforces `oldSwapchain` for seamless recreation**), `xvk_destroy_swapchain_khr`, `xvk_get_swapchain_images_khr`, `xvk_acquire_next_image_khr` (semaphore *and* fence), `xvk_queue_present_khr` (multi-swapchain-capable `VkPresentInfoKHR`), all four surface query functions, plus:
- `VK_KHR_get_surface_capabilities2` (caps2, formats2)
- `VK_KHR_display` -- 7 functions (direct-to-display rendering)
- `VK_EXT_headless_surface`
- `VK_EXT_hdr_metadata`
- `VK_EXT_full_screen_exclusive` (present modes 2)
- `VK_KHR_shared_presentable_image` (`vkGetSwapchainStatusKHR`)
- Human-readable `VkResult` names in errors; `_Static_assert` ABI guards on 7 structs

**Status: FULL+** -- exceeds typical engine bridge coverage.

### 🔴 REGRESSION BUG -- `recreate_swapchain` (`xvk_swapchain.c:270-287`)

The old monolith's `recreate_swapchain` rebuilt **swapchain → depth → framebuffers → command buffers**. The new split version only does:

```c
cleanup_swapchain(a);            /* frees framebuffers (sets NULL) */
vkFreeCommandBuffers(...);       /* frees cmd_buffers (sets NULL)  */
create_swapchain(a);
create_depth_resources(a);
return 1;                        /* framebuffers + cmd_buffers STILL NULL */
```

`create_framebuffers()` / `allocate_cmd_buffers()` are now called **only** in `xvk_app_create` (`xvk_app.c:410,418`). After a window resize, the next `xvk_begin_frame` (extents now match) dereferences `a->cmd_buffers[img_idx]` (`xvk_frame.c:45`) and `a->framebuffers[img_idx]` (`xvk_frame.c:67`) -- **NULL pointer crash**. The windowed legacy path breaks on first resize. Fix: restore the two rebuild steps at the end of `recreate_swapchain`.

---

## 3. Render Pass / Framebuffer

- Legacy: windowed colour+depth pass, offscreen colour pass (final layout TRANSFER_SRC), configurable generic pass (`xvk_render_pass_create` -- load/store ops, final layouts, optional depth), framebuffer creation, custom-pass begin/end with auto re-begin of the default pass.
- Raw: `xvk_create_render_pass` / `xvk_create_framebuffer` from caller-built structs (**any subpass count, input attachments, resolve attachments, MSAA attachments expressible**), plus `vkCmdBeginRenderPass2` / `vkCmdNextSubpass` / `vkCmdNextSubpass2` / `vkCmdEndRenderPass2` (1.2-gated) and **dynamic rendering**: `vkCmdBeginRendering` / `vkCmdEndRendering` (1.3 core) + `vkCmdBeginRenderingKHR` / `vkCmdEndRenderingKHR` (extension alias fallback).

Missing: `vkCreateRenderPass2` (device-side creation of RP2 -- begin/end2 exist but pass creation uses v1 struct; input-attachment-heavy RP2 features like `VkAttachmentDescription2` pNext chains not reachable), `vkGetRenderAreaGranularity`.

**Status: FULL** for practical purposes.

---

## 4. Pipelines

- Legacy: 5 built-in graphics pipelines (2D tri, 3D cube, quad, particle, offscreen) + generic `xvk_pipeline_create_graphics` (topology/cull/depth/blend/vertex-layout config, still fixed-viewport) + `xvk_pipeline_create_compute` + `xvk_compute_dispatch`.
- Raw (`xvk_bind_pipeline.c`): `xvk_create_graphics_pipelines` / `xvk_create_compute_pipelines` -- batch creation from **caller-built `VkGraphicsPipelineCreateInfo[]`** with a real `VkPipelineCache` parameter. Tessellation/geometry stages, MSAA states, dynamic-state lists, derivatives, and specialization constants are all expressible since the struct is caller-authored. `xvk_create_pipeline_cache` / `xvk_destroy_pipeline_cache` exist.

Missing: `vkGetPipelineCacheData` / `vkMergePipelineCaches` -- a pipeline cache can be created and used within a run but **cannot be serialized to disk or merged**, negating its main benefit across runs.

**Status: FULL** minus cache serialization.

---

## 5. Shader Modules

- Legacy: embedded SPIR-V table (15 named shaders incl. compute), raw-bytes creation.
- Raw: `xvk_create_shader_module` from caller struct; **`VK_EXT_shader_object`** (`vkCreateShadersEXT`, `vkDestroyShaderEXT`, `vkCmdBindShadersEXT`) for pipeline-less shaders.

**Status: FULL.**

---

## 6. Command Buffers / Draws / Copies

Raw layer (`xvk_bind_command.c`, 685 lines) covers:

| Category | Functions |
|---|---|
| Lifecycle | `vkCreateCommandPool`, `vkDestroyCommandPool`, `vkResetCommandPool`, `vkAllocateCommandBuffers` (level from caller struct → **secondary CBs supported**), `vkFreeCommandBuffers`, `vkBeginCommandBuffer` (default-info fallback), `vkEndCommandBuffer` |
| Draw / dispatch | `vkCmdDraw`, `vkCmdDrawIndexed`, `vkCmdDrawIndirect`, `vkCmdDrawIndirectCount` (1.2), `vkCmdDrawIndexedIndirectCount` (1.2), `vkCmdDispatch`, `vkCmdDispatchIndirect`, `vkCmdDispatchBase` (1.1) |
| Binds | `vkCmdBindPipeline` (any bind point), `vkCmdBindVertexBuffers` (multi-buffer), `vkCmdBindIndexBuffer`, `vkCmdBindDescriptorSets` (**dynamic offsets supported**), `vkCmdPushConstants`, `vkCmdBindDescriptorSets2` + `vkCmdPushConstants2` (1.4-gated) |
| Secondary | `vkCmdExecuteCommands` |
| Copies / clears | `vkCmdCopyBuffer`, `vkCmdCopyImage`, `vkCmdCopyBufferToImage`, `vkCmdCopyImageToBuffer`, `vkCmdBlitImage` (**mipmap generation now possible**), `vkCmdUpdateBuffer`, `vkCmdFillBuffer`, `vkCmdClearColorImage`, `vkCmdClearDepthStencilImage`, `vkCmdClearAttachments`, `vkCmdResolveImage` (**MSAA resolve**) |
| Barriers | `vkCmdPipelineBarrier` (all 3 barrier arrays), `vkCmdPipelineBarrier2` (1.3) |
| Multi-GPU | `vkCmdSetDeviceMask` (1.1) |
| Addresses | `vkGetBufferDeviceAddress`, `vkGetBufferOpaqueCaptureAddress`, `vkGetDeviceMemoryOpaqueCaptureAddress` (1.2) |

**Gap:** plain **`vkCmdDrawIndexedIndirect` is absent** -- the non-indexed indirect and both `*Count` variants exist, so indexed indirect drawing requires a count buffer (1.2 path) as a workaround. One-line fix.

**Status: FULL** minus that one entry point.

---

## 7. Descriptors

- Legacy: layout/pool/set lifecycle, buffer + combined-image-sampler writes (4 descriptor types via enum map, GRAPHICS-only bind point in `xvk_app_cmd_bind_descriptor_sets`).
- Raw (`xvk_bind_descriptor.c`): all creation from caller structs (**every `VkDescriptorType` expressible**), `vkUpdateDescriptorSets` with **writes AND copies**, `vkCreateDescriptorUpdateTemplate` / destroy, and from the extension module: **`vkCmdPushDescriptorSetKHR`** + `vkCmdPushDescriptorSetWithTemplateKHR` (core-alias fallback).

**Status: FULL.** (Descriptor indexing / variable counts reachable via caller-built binding-flags pNext chains.)

---

## 8. Buffers / Memory

- Raw buffer: `xvk_create_buffer` (caller struct → any usage flags incl. indirect, SSBO, BDA), `xvk_bind_buffer_memory` (**arbitrary offset → sub-allocation now possible from XIOM side**), `xvk_get_buffer_memory_requirements`, **`vkCreateBufferView` / `vkDestroyBufferView`** (texel buffers -- new).
- Raw memory (`xvk_bind_memory.c`): `vkAllocateMemory` (pNext chain via struct → dedicated allocation / BDA flags expressible), `vkFreeMemory`, `vkMapMemory` (offset/size/`VK_WHOLE_SIZE`), `vkUnmapMemory`, **`vkFlushMappedMemoryRanges` / `vkInvalidateMappedMemoryRanges`** (non-coherent memory now correctly supported -- was missing).
- Legacy buffer API unchanged (1:1 alloc, host-visible map/write/read).

Missing: `vkBindBufferMemory2` / `vkBindImageMemory2`, `vkGetBufferMemoryRequirements2` / `vkGetImageMemoryRequirements2`, `vkGetDeviceMemoryCommitment`, sparse binding (`vkQueueBindSparse`, `vkGetImageSparseMemoryRequirements`).

**Status: FULL** for non-sparse workflows.

---

## 9. Images / Views / Samplers

- Raw: `xvk_create_image` from caller struct (**3D images, cubemaps, array layers, MSAA samples, linear tiling all expressible**), `xvk_bind_image_memory` (offset), `xvk_create_image_view` (any view type via struct), `xvk_create_sampler` (any sampler state incl. anisotropy -- device feature is now enabled).
- `VK_EXT_host_image_copy`: `vkCopyMemoryToImageEXT`, `vkCopyImageToMemoryEXT`, `vkCopyImageToImageEXT`, `vkTransitionImageLayoutEXT` (host-side layout transitions without a command buffer).
- Legacy: 2D-only creation, color/depth aspects, sampler with anisotropy still hardcoded OFF (`xvk_buffer.c:238`) despite the feature now being enabled -- minor inconsistency.
- Legacy `xvk_image_transition` still color-aspect-only with 3 special-cased transitions + catch-all.

Missing: `vkGetImageSubresourceLayout` (linear-tiling readback stride query).

**Status: FULL** via raw layer; legacy convenience path remains basic.

---

## 10. Synchronization

- Raw (`xvk_bind_sync.c`): `vkCreateFence` (signaled via caller flags), `vkWaitForFences` (any count, wait-all flag, timeout), `vkResetFences`, `vkCreateSemaphore` (**timeline semaphores via `VkSemaphoreTypeCreateInfo` pNext chain**), **`vkCreateEvent` / `vkDestroyEvent`**, `vkQueueSubmit` (multi-submit, raw `VkSubmitInfo[]`).
- Command-side events: `vkCmdSetEvent`, `vkCmdResetEvent`, `vkCmdWaitEvents` (full barrier arrays) + sync2 variants `vkCmdSetEvent2` / `vkCmdResetEvent2` / `vkCmdWaitEvents2` (1.3-gated).
- Sync2: `vkCmdPipelineBarrier2` (core), `vkCmdPipelineBarrier2KHR`, `vkQueueSubmit2KHR`, `vkCmdWriteTimestamp2KHR` (alias fallback to core names).
- Timeline ops (ext module, core-alias fallback): `vkGetSemaphoreCounterValueKHR`, `vkWaitSemaphoresKHR`, `vkSignalSemaphoreKHR`.
- Legacy: per-frame binary semaphores + fences, 2 frames in flight (unchanged).

Missing: host-side `vkSetEvent` / `vkResetEvent` / `vkGetEventStatus` (events can be created and used on GPU but not signalled from CPU), `vkGetFenceStatus` (non-blocking poll), `vkQueueWaitIdle`.

**Status: FULL** minus host event ops.

---

## 11. Dynamic State -- previously the biggest gap, now COMPLETE

**Core 1.0** (`xvk_bind_command.c:426-483`): `vkCmdSetViewport` (multi, first/count), `vkCmdSetScissor`, `vkCmdSetLineWidth`, `vkCmdSetDepthBias`, `vkCmdSetBlendConstants`, `vkCmdSetDepthBounds`, `vkCmdSetStencilCompareMask` / `WriteMask` / `Reference` -- **all 9 present**.

**Extended dynamic state 1/2/3 + friends** (`xvk_bind_extensions.c`, EXT→core alias fallback): cull mode, front face, primitive topology, viewport/scissor with count, depth test/write/compare enable, stencil test enable, stencil op, rasterizer discard, depth-bias enable, primitive restart, **polygon mode, rasterization samples, sample mask, alpha-to-coverage, color blend enable/equation/write mask, logic op, color write enable, vertex input (dynamic!)** -- 22 more setters.

Note: pipelines built through the raw layer supply their own `VkPipelineDynamicStateCreateInfo`, so these setters are fully usable. The legacy app-layer pipelines still bake viewport/scissor (unchanged), acceptable for that convenience path.

**Status: FULL.**

---

## 12. Query Pools -- previously absent, now dual-layer

- Simplified (`xvk_query.c`): `xvk_query_pool_create` (occlusion / timestamp / pipeline-statistics), destroy, `xvk_query_write_timestamp` (hardcoded BOTTOM_OF_PIPE), `xvk_query_pool_get_results` (64-bit, WAIT).
- Raw (`xvk_bind_query.c`): `vkCreateQueryPool` (caller struct → pipeline-statistics flags expressible), `vkGetQueryPoolResults` (any stride/flags), `vkCmdBeginQuery`, `vkCmdEndQuery`, `vkCmdWriteTimestamp` (any stage), `vkCmdResetQueryPool`, `vkCmdCopyQueryPoolResults` (GPU-side readback).

Missing: host `vkResetQueryPool` (1.2), performance-query extensions.

**Status: FULL.**

---

## 13. Ray Tracing -- previously absent, now fully bound (`xvk_bind_raytracing.c`, 989 lines)

Per-device proc cache (up to 8 devices) via `vkGetDeviceProcAddr`; `xvk_raytracing_load_device_procs` returns a capability bitmask.

| Extension | Coverage |
|---|---|
| `VK_KHR_acceleration_structure` | create/destroy, build sizes, `vkCmdBuildAccelerationStructures(Indirect)KHR`, all 3 copy commands + host copy, properties→query pool, device address, compatibility -- **12/12 entry points** |
| `VK_KHR_ray_tracing_pipeline` | pipeline creation (with deferred-op + cache params), `vkCmdTraceRaysKHR`, `vkCmdTraceRaysIndirectKHR`, shader-group handles (+ capture replay), group stack size, `vkCmdSetRayTracingPipelineStackSizeKHR` -- **7/7** |
| `VK_NV_ray_tracing` (legacy) | pipelines, AS create/destroy/mem-reqs/bind, build/copy/trace, group + AS handles, properties, `vkCompileDeferredNV` -- **12/12** |
| `VK_EXT_micromap` | create/destroy, build (cmd + host), 3 copies, properties, compatibility, build sizes -- **11/11**, with graceful ABI-stable stubs when SDK < 1.3.230 |

Missing: `VK_KHR_deferred_host_operations` (`vkCreateDeferredOperationKHR` / `Destroy` / `Join` / `GetResult`) -- RT functions **accept** deferred-op handles but XIOM cannot create one, so all RT builds are effectively synchronous. Also `VK_KHR_ray_query` needs no entry points (shader-side) and is enableable via device pNext.

**Status: FULL bindings** minus deferred host operations.

---

## 14. Extension Modules (`xvk_bind_extensions.c`, 915 lines)

Lazy proc resolution with generation-counted caches (`xvk_ext_load_instance` / `xvk_ext_load_device` invalidate on reload); EXT→core alias fallback where promoted.

| Extension | Entry points |
|---|---|
| `VK_EXT_debug_utils` | messenger create/destroy (tracked, up to 16), object name/tag, queue + cmd labels (begin/end/insert) -- 9 |
| `VK_EXT_mesh_shader` | draw mesh tasks, indirect, indirect count -- 3 |
| Extended dynamic state 1/2/3, color-write-enable | 22 (listed in S11) |
| `VK_EXT_conditional_rendering` | begin/end -- 2 |
| `VK_EXT_transform_feedback` | bind buffers, begin/end -- 3 |
| `VK_KHR_push_descriptor` | push set, push with template -- 2 |
| `VK_KHR_fragment_shading_rate` | set shading rate -- 1 |
| `VK_EXT_sample_locations` (+EDS3 enable) | 2 |
| `VK_EXT_line_rasterization` | line stipple -- 1 |
| `VK_KHR_copy_commands2` | copy buffer/image 2, blit2, buffer↔image 2, resolve2 -- 6 |
| `VK_EXT_host_image_copy` | 4 (listed in S9) |
| `VK_KHR_timeline_semaphore` | 3 (listed in S10) |
| `VK_KHR_dynamic_rendering` | 2 |
| `VK_KHR_synchronization2` | 3 |
| `VK_EXT_shader_object` | 3 |
| `VK_KHR_video_queue` / `decode` / `encode` | session + parameters lifecycle, memory binding, begin/end/control coding, decode, encode -- 11 |

**Status:** exceptional breadth for a language bridge.

---

## 15. Remaining Gaps (consolidated)

### Bugs
| Severity | Issue |
|---|---|
| 🔴 HIGH | `recreate_swapchain` (`xvk_swapchain.c:270`) no longer rebuilds framebuffers or reallocates command buffers → **NULL deref crash after window resize** in the legacy windowed path (regression vs. the monolith) |
| 🟡 LOW | `xvk_frame.c:18` treats both success and failure of `recreate_swapchain` as "skip frame" -- masks the above |
| 🟡 LOW | Legacy `xvk_sampler_create` still forces `anisotropyEnable = VK_FALSE` although the device now enables `samplerAnisotropy` |

### Missing Vulkan entry points (raw layer)
| Priority | Entry points |
|---|---|
| High | `vkCmdDrawIndexedIndirect` (plain; both Count variants exist) |
| High | `vkGetPipelineCacheData`, `vkMergePipelineCaches` (cache cannot persist across runs) |
| Medium | `vkGetPhysicalDeviceFeatures(2)`, `vkGetPhysicalDeviceProperties2`, `vkGetPhysicalDeviceFormatProperties(2)`, `vkGetPhysicalDeviceImageFormatProperties`, `vkEnumerateInstance/DeviceExtensionProperties` -- features can be enabled but not queried |
| Medium | Host event ops: `vkSetEvent`, `vkResetEvent`, `vkGetEventStatus`; `vkGetFenceStatus`; `vkQueueWaitIdle` |
| Medium | `VK_KHR_deferred_host_operations` (create/join/destroy) -- blocks async RT builds |
| Low | `vkBindBufferMemory2` / `vkBindImageMemory2`, `vkGet*MemoryRequirements2` |
| Low | Host `vkResetQueryPool` (1.2) |
| Low | `vkCreateRenderPass2` (begin/next/end 2 exist) |
| Low | Sparse resources: `vkQueueBindSparse`, `vkGetImageSparseMemoryRequirements` |
| Low | `vkGetImageSubresourceLayout`, `vkGetRenderAreaGranularity`, `vkGetDeviceMemoryCommitment` |

### Legacy-layer limitations (unchanged, by design -- raw layer supersedes them)
- App pipelines bake viewport/scissor; window resize requires swapchain+pipeline rebuild
- Legacy pipelines fixed at 1x MSAA; `xvk_app_cmd_bind_descriptor_sets` graphics-bind-point only
- `xvk_image_transition` color-aspect only; simplified timestamps pinned to BOTTOM_OF_PIPE
- 1:1 buffer↔memory allocation in the convenience API

---

## 16. Verification Data

- Unique direct `vk*` calls compiled in: **154** (grep-verified across all 29 `.c` files)
- Runtime-resolved entry points (`vkGetInstanceProcAddr` / `vkGetDeviceProcAddr`): **~90** (extensions, swapchain2, ray tracing, video)
- Exported `xvk_*` ABI functions: **368** (~280 raw bindings, ~88 legacy/app/marshalling)
- ABI safety: `_Static_assert` size/offset checks in `xvk_bind_instance.c`, `xvk_bind_device.c`, `xvk_bind_swapchain.c`; magic-number handle validation throughout the legacy layer; every fallible call reports `VkResult` through `xvk_last_error()`

### Coverage by Vulkan core version
| Version | Coverage | Notes |
|---|---|---|
| 1.0 core | ~96% | Missing: sparse, host event ops, a few getters, plain indexed-indirect |
| 1.1 core | ~50% | Has dispatch base, device mask, update templates; missing get2/bind2/features2, protected memory, YCbCr conversion objects |
| 1.2 core | ~75% | Has draw-indirect-count, BDA, renderpass2 cmds, timeline (via alias); missing host reset-query, `vkCreateRenderPass2` |
| 1.3 core | ~85% | Has dynamic rendering, sync2, EDS via alias; missing `vkGetDeviceBufferMemoryRequirements` family |
| 1.4-gated | present | `vkCmdBindDescriptorSets2`, `vkCmdPushConstants2` (compile-gated) |

---

*Report generated by XIOM Kilo re-audit, 2026-07-18. Previous audit (monolithic bridge, ~87%) superseded.*
