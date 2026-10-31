# xiom.vulkan

Vulkan bindings for XIOM via a **dynamic loader**: no SDK, no headers, no
link-time dependency. `vulkan-1.dll` is resolved at runtime and every
struct crossing the boundary is declared with pinned ABI layouts in our own
header-free C bridge.

> **Status:** `incubating` -- **engine RHI bring-up + WSI + render pipeline +
> capture/query (0.6.0)**: capability probe; instance/device/queue + real
> submit; hidden Win32 window + `VkSurfaceKHR` + swapchain + clear/present;
> render pass + graphics pipeline from embedded SPIR-V + **3-vertex draw with
> pixel readback** (center rgb(0,255,0) triangle over the 0.1/0.2/0.3 clear,
> verified by `vkCmdCopyImageToBuffer`); **C07 stable capture-copy** (full
> frame bytes + FNV-1a checksum compared across frames) and **B05 query
> readback** (timestamp begin/end + `timestampPeriod` -> per-pass duration;
> occlusion sample count). Suite **24/24 x2** on the RTX 3070 Ti (v0.65.4).
> Raw commands: `docs/CAPTURE-QUERY.md`. **Lane:** bindings
> (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.vulkan;

fn main() {
  // Capability probe (SKIP-friendly in CI).
  let p = vulkan_probe();
  if !p.is_ok { io.println("Vulkan unavailable: " + p.error.message); return; }
  let info: VulkanInfo = p.value;
  io.println(info.device_name + " | loader "
    + to_string(vulkan_api_major(info.api_version)) + "."
    + to_string(vulkan_api_minor(info.api_version)));

  // Full render round trip: clears, draws a triangle, presents (2 frames).
  let t = vulkan_triangle_probe(2);
  if t.is_ok {
    let v: VulkanTriangle = t.value;
    io.println("triangle frames=" + to_string(v.frames)
      + " center=" + to_string(v.center_pixel)
      + " corner=" + to_string(v.corner_pixel));
  } else {
    io.println("triangle: " + t.error.message);  // SKIP in CI
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Probe | `vulkan_probe`, `vulkan_probe_named(soname)` |
| Extensions | `vulkan_has_extension(name)`, `vulkan_has_extension_named(soname, name)` |
| RHI bring-up | `vulkan_rhi_probe[_named]` -- instance + surface exts, discrete-preferred device, graphics queue family, logical device + queue, command pool + **real submit/wait**; `VulkanRhi` |
| WSI | `vulkan_wsi_probe[_named](frames)` -- hidden window -> surface -> swapchain -> acquire/clear/present cycles; `VulkanWsi` |
| Render | `vulkan_triangle_probe[_named](frames[, r,g,b])` -- render pass + graphics pipeline (embedded SPIR-V) + 3-vertex draw + copy-to-buffer readback + present; `VulkanTriangle` (center/corner pixels packed `r<<16|g<<8|b`) |
| Capture/query (0.6.0) | `VulkanTriangle`: `capture_bytes`, `capture_crc`, `capture_stable` (C07 full-frame copy stability), `query_ok`, `timestamp_begin/end`, `timestamp_period_ns`, `duration_ns`, `occlusion_samples` (B05). Raw sequence + offsets: `docs/CAPTURE-QUERY.md` |
| Kinds | `VULKAN_LOAD_ABSENT` (SKIP), `VULKAN_LOAD_NO_DEVICE` (SKIP), `VULKAN_LOAD_ABI` (FAIL) |
| Helpers | `vulkan_api_major/minor/patch`, `VK_PHYSICAL_DEVICE_TYPE_*`, `VULKAN_SONAME` |

Failure model: loader missing -> SKIP; no compatible driver instance -> SKIP;
missing entry points/RHI step -> FAIL. A bogus soname exercises the SKIP path
deterministically in every suite run.

## Build note

`port.args.json` compiles the header-free bridges
(`src/vk_probe.c` + `src/vk_rhi.c`) and links `user32` for the hidden
window. Shaders are compiled with
`C:\VulkanSDK\1.4.350.0\Bin\glslc.exe` and embedded via
`tools/embed_spv.py` (`src/shaders/*` committed next to `src/tri_*_spv.inc`):

```
glslc src/shaders/tri.vert -o src/shaders/tri.vert.spv
python tools/embed_spv.py tri_vert_spv src/shaders/tri.vert.spv src/tri_vert_spv.inc
```

## Tests

```
scripts/port.ps1 -Package xiom.vulkan
```

Expected: 24 `[PASS]`, exit 0 (loader 1.4.350, RTX 3070 Ti; ~25 s including
the two triangle frames and the capture/query readback). G2 pin + re-pin:
`SPEC.md` §2.
