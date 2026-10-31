# SPEC: xiom.vulkan -- Vulkan capability probe + engine RHI bring-up via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.vulkan` |
| Version | 0.7.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Vulkan (Khronos); Windows loader `vulkan-1.dll` |
| Upstream license | Apache-2.0 (headers); no headers or code vendored -- the bridge is our code and declares the minimal ABI locally |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (system loader `vulkan-1.dll`, driver-installed in System32) |
| Compiler pin | v0.65.4 |

## 2. G2 pin: soname + header hash + entry-point set

**Soname (runtime contract):** `vulkan-1.dll`. Resolved at runtime via
`LoadLibraryA` + `vkGetInstanceProcAddr`; no SDK, no headers, no link-time
dependency, nothing vendored.

**Header pin** (fetched verbatim from
`https://raw.githubusercontent.com/KhronosGroup/Vulkan-Headers/vulkan-sdk-1.4.350.0/include/vulkan/vulkan_core.h`):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `vulkan_core.h` (tag `vulkan-sdk-1.4.350.0`) | 1,317,089 | `6D2BA4755774B1D129DA6B8E661268B494D2D609DF6217C6B6485ACF7666B6C2` |

**Resolved entry points** (the ABI this package depends on):
`vkGetInstanceProcAddr` (from the DLL) then, via it:
`vkEnumerateInstanceVersion` (optional, absent on 1.0 loaders),
`vkEnumerateInstanceExtensionProperties`, `vkEnumerateInstanceLayerProperties`,
`vkCreateInstance`; instance-scoped (resolved with the instance handle):
`vkEnumeratePhysicalDevices`, `vkGetPhysicalDeviceProperties`,
`vkDestroyInstance`.

**ABI details pinned:** `VK_STRUCTURE_TYPE_APPLICATION_INFO=0`,
`INSTANCE_CREATE_INFO=1`; requested `apiVersion` = `VK_MAKE_API_VERSION(0,1,0,0)`;
`VkExtensionProperties` = `char name[256] + u32 specVersion`;
`VkLayerProperties` = `char layerName[256] + u32 + u32 + char description[256]`;
`VkPhysicalDeviceProperties` prefix = `apiVersion(0) driverVersion(4) vendorID(8)
deviceID(12) deviceType(16) deviceName(20, 256)` -- received into an oversized
opaque buffer so the full struct write stays in bounds.

**0.3.0 RHI bridge ABI additions** (`src/vk_rhi.c`): local declarations for
APPLICATION_INFO(0), INSTANCE_CREATE_INFO(1), DEVICE_QUEUE_CREATE_INFO(2),
DEVICE_CREATE_INFO(3), SUBMIT_INFO(4), COMMAND_POOL_CREATE_INFO(39),
COMMAND_BUFFER_ALLOCATE_INFO(40), COMMAND_BUFFER_BEGIN_INFO(42); graphics
family via `VK_QUEUE_GRAPHICS_BIT`; `VkQueueFamilyProperties` stride 24
(flags/queueCount/timestampValidBits). The instance enables
`VK_KHR_surface` + `VK_KHR_win32_surface` when the loader has them
(reported as `surface_extensions`). The sequence instance -> device pick
(discrete preferred) -> graphics family -> logical device + queue ->
command pool/buffer begin/end -> `vkQueueSubmit` + `vkQueueWaitIdle` runs
headless and crosses the XIOM boundary as scalars/strings only
(B-11/B-12 discipline).

**0.4.0 WSI additions** (`src/vk_rhi.c`, build order #2): hidden Win32
window (user32 linked via `port.args.json` `--link user32`),
`XwWin32SurfaceCreateInfo` (1000009000), swapchain creation (1000001000;
FIFO; B8G8R8A8 preferred; extent from surface caps; min+1 images),
`XwImageMemoryBarrier` (45; UNDEFINED -> TRANSFER_DST -> PRESENT_SRC),
`vkCmdClearColorImage`, acquire/submit/present with binary semaphores,
`XwPresentInfo` (1000001002). The logical device enables `VK_KHR_swapchain`
when the GPU offers it -- device-level lookups otherwise return null. The
suite runs 3 real clear+present cycles on a never-shown popup window
(`xw_window_create` -> `xw_surface` -> `xw_swapchain` -> `xw_frames`).

**0.5.0 render-pipeline additions** (`src/vk_rhi.c`, build order #3): render
pass (`XwRenderPassCreateInfo` 38; one attachment, loadOp CLEAR, finalLayout
TRANSFER_SRC, one subpass, one dependency), image views (15, type 2D=1) +
framebuffers (37), shader modules (16) from embedded SPIR-V
(`src/shaders/tri.vert|frag` via glslc + `tools/embed_spv.py` ->
`src/tri_*_spv.inc`), pipeline layout (30), graphics pipeline (28) with
empty vertex input, TRIANGLE_LIST, static viewport/scissor, color blend
write-mask 0xF; `XwRenderPassBeginInfo` (43) + clear value; draw 3 verts;
`vkCmdCopyImageToBuffer` into a HOST_VISIBLE|HOST_COHERENT buffer
(allocation path: 12/5 + requirements + memory types from
`vkGetPhysicalDeviceMemoryProperties`, types at offset 4, stride 8);
barriers COLOR_ATTACHMENT_WRITE->TRANSFER_READ (layout 6->6) and
TRANSFER_WRITE->bottom (6->PRESENT_SRC). Constants pinned from the header
grep: TRANSFER_SRC=6 / TRANSFER_DST=7 (the 0.4.0 clear path's constant was
corrected 6->7), ACCESS TRANSFER_READ=0x800, VIEW_TYPE_2D=1,
STAGE_COLOR_ATTACHMENT_OUTPUT=0x400. Readback pixels cross the boundary as
`r<<16 | g<<8 | b`.

**0.6.1 capture/query additions** (`src/vk_rhi.c`, engine ask
`REL-20261031-1423-engine-4`; the raw command surface in
`src/api.xi` + `src/cmds_01..08.xi` already binds every command used here).
0.6.0 is the published SDK100 raw-surface cut and is immutable, so the
capture/query helper ships as 0.6.1:
`XwQueryPoolCreateInfo` (32 bytes; sType 11, pNext 8, flags 16, queryType
20, queryCount 24, pipelineStatistics 28), a 2-query TIMESTAMP pool and a
1-query OCCLUSION pool; `vkCmdResetQueryPool`, `vkCmdWriteTimestamp` at
`COLOR_ATTACHMENT_OUTPUT` before/after the draw, `vkCmdBeginQuery`/
`vkCmdEndQuery` around it, and `vkGetQueryPoolResults` with
`64_BIT(1)|WAIT(2)`. The helper computes a FNV-1a checksum over the full
`extent_w * extent_h * 4` readback frame and compares it across frames
(C07 stable capture-copy), and returns `timestamp_begin/end`,
`timestamp_period_ns` (read from `VkPhysicalDeviceProperties.limits` at
absolute offset 716: limits 292 + timestampPeriod 424), `duration_ns` and
`occlusion_samples` (B05). `timestampValidBits` is read from the chosen
graphics family (`VkQueueFamilyProperties` offset 8); the query stage is
best-effort (the draw still renders when a device exposes no timestamps).
The suite asserts a stable 307200-byte frame checksum, a non-zero duration
and non-zero occlusion samples on the pinned host. The exact raw sequence,
struct offsets and the engine-owned-command-buffer recipe are pinned in
`docs/CAPTURE-QUERY.md`.

**Local runtime sample used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| System loader | `C:\Windows\System32\vulkan-1.dll`, 1,740,728 bytes, FileVersion 1.4.350.0, SHA256 `0419974F00E82A3D619077BA414DA265A774F8DB9D45AD93BC1843F44B2C2C1F` |
| SDK header copy (reference) | `C:\VulkanSDK\1.4.350.0\Include\vulkan\vulkan_core.h`, 1,343,384 bytes, SHA256 `2F7AA635DB9A068294C70DE0F90D74C869602C132C30F306CB73B973A3F9B502` |
| Runtime report | loader API 1.4.350; 20 instance extensions; 15 layers; device `NVIDIA GeForce RTX 3070 Ti` (type 2 = discrete, api 1.4) |

### Re-pin procedure

1. Pick the new Khronos tag; re-fetch `include/vulkan/vulkan_core.h`,
   recompute the SHA256, update this table and the version rows in
   `README.md`/`AUDIT.md` in one commit.
2. If the entry-point set grows, update `vk_probe.c` + `vulkan.xi` in the same
   commit; missing required entry points fail closed (`VULKAN_LOAD_ABI`).
3. Re-run `scripts/port.ps1 -Package xiom.vulkan` and record the matrix in Â§4.

## 3. Design

- `src/vk_probe.c` (our code, MIT/Apache) includes **no Vulkan headers**: the
  instance-create structs are declared locally (the bridge is the writer) and
  everything the loader writes back goes into oversized opaque buffers. It
  links nothing but kernel32 and needs no `--link` flags.
- The XIOM module (`vulkan.xi`, module `xiom.vulkan`) is a thin safe wrapper;
  all `unsafe`/`extern` in this package are confined to this single module
  (G5). Public API: `vulkan_probe`, `vulkan_probe_named`,
  `vulkan_has_extension`, `vulkan_has_extension_named`, `VulkanInfo`,
  `VulkanLoadError`, version helpers and constants.
- **Classification**: loader missing -> `VULKAN_LOAD_ABSENT` (SKIP);
  `vkCreateInstance` fails (no ICD/driver) -> `VULKAN_LOAD_NO_DEVICE` (SKIP);
  entry points missing -> `VULKAN_LOAD_ABI` (FAIL). Probes are atomic
  (load -> query -> instance -> device -> unload); a bogus soname exercises
  the SKIP path deterministically on any host.
- **Build:** `port.args.json` compiles the bridge
  (`--c-source ${PACKAGE_DIR}/src/vk_probe.c`).
- The pre-pilot package shipped a ~1.7 MB static-bridge game engine
  (`bridge/xvk_*`, stb headers, shaders, build.ps1/build.sh) that required the
  Vulkan SDK at build time and could not satisfy the SKIP-when-absent gate; it
  is preserved in git history and its scope returns over this loader in
  later phases (`ROADMAP.md`, `AUDIT.md`).

## 4. Test matrix (recorded 2026-10-31, compiler v0.65.4)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vulkan present (System32 loader 1.4.350) | `scripts/port.ps1 -Package xiom.vulkan` | **PASS 36/36 x2** -- probe surface + RHI bring-up (queue 0, real submit) + WSI (320x240, format 44, 3 images, 3 clear+present) + triangle (2 frames; center pixel rgb(0,255,0), bottom-left sample rgb(25,51,76) = the clear) + stable 307200-byte capture checksum + timestamp duration (3072 ns @ 1 ns/tick) + occlusion samples (24576) on the RTX 3070 Ti |
| Loader absent (CI shape) | not reproducible on this host (driver-installed loader); the bogus-soname classification runs in every suite invocation | SKIP path exercised + code-reviewed |
| No ICD/driver | not reproducible on this host; instance failure maps to `VULKAN_LOAD_NO_DEVICE` (SKIP) | code-reviewed |

## 5. Scope

Engine RHI bring-up + WSI + render pipeline over the loader seam: capability
probe, instance/device/queue + submit, hidden-window surface + swapchain +
clear/present, the triangle pipeline (render pass + embedded SPIR-V +
3-vertex draw + readback + present), and the C07 capture-copy / B05 query
readback helper (`docs/CAPTURE-QUERY.md`). Compute pipelines, descriptors,
textures, depth/stencil and per-frame synchronization are later phases
(`ROADMAP.md`).
