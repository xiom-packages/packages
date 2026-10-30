# xiom.imgui

Dear ImGui v1.92.9b bindings for XIOM. The upstream core, its headless
null backends, and the SDL3 platform + Vulkan renderer backends are
vendored into `vendor/` (MIT) and compiled into the test binary with
`--c-source` -- no precompiled objects. The SDL3 and Vulkan-Headers trees
plus the import libs come from Vulkan SDK 1.4.350.0 (SDL 3.4.8); the
runtime needs `SDL3.dll` and `vulkan-1.dll`, no SDK at run time.

> **Status:** `incubating` -- conformance suite **11/11 x2** on v0.65.3.
> **0.4.0 published 2026-10-30** as single tag `xiom-imgui/v0.4.0` (sha256
> `a60d80a5...`); the vendored import libs are tracked and hash-pinned, and
> the publish workflow force-packs them only for this package. 0.3.0 was
> `xiom-imgui/v0.3.0` (sha256 `1a7feb3d...`).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.imgui;

fn main() {
  io.println("Dear ImGui " + imgui_version_str());

  let f = imgui_frame();
  if f.is_ok {
    io.println("frame tessellated (see ImguiFrameStats)");
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Version | `imgui_version` (packed, 19291), `imgui_version_str` ("1.92.9b") |
| Frames | `imgui_frame` -> `ImguiFrameStats` (vertices/indices/cmd_lists), `imgui_empty_frame` -> cmd_lists |
| Contexts | `imgui_context_create(width, height)` -> handle (<=4 live), `imgui_context_frame(handle)` -> stats, `imgui_context_destroy(handle)`, `imgui_context_count`, `imgui_context_frames` |
| Backends (0.4.0) | `imgui_backend_create` -> handle (<=2 live), `imgui_backend_sdl3_init(handle, window, for_vulkan)`, `imgui_backend_sdl3_process_event(handle, event_ptr)`, `imgui_backend_vulkan_init(handle, instance, phys, device, queue, family, pool, render_pass, api_version, min_images, images, msaa, subpass)`, `imgui_backend_frame(handle)` -> stats, `imgui_backend_draw_data`, `imgui_backend_vulkan_render(handle, draw_data, cmd)`, `imgui_backend_shutdown`, `imgui_backend_sdl3_selftest`, `imgui_backend_last_error` |

Full details: `SPEC.md`; vendored provenance + per-file pin: `SPEC.md` §2.

### Backend interop (engine-owned)

The engine keeps ownership of every object; the bridge only consumes
handles:

- **Platform**: `imgui_backend_sdl3_init(handle, sdl_window, true)` for the
  Vulkan renderer, or `false` for `InitForOther`. Feed events with
  `imgui_backend_sdl3_process_event` (pointer to the `SDL_Event` you got
  from `SDL_PollEvent`).
- **Renderer**: `imgui_backend_vulkan_init` needs the engine's
  `VkInstance`, physical device, `VkDevice`, `VkQueue`, queue family,
  `VkDescriptorPool` and `VkRenderPass` (a real render pass; dynamic
  rendering is a follow-up), plus the image counts, MSAA sample count and
  subpass. The pool must meet imgui's minimum sampled-image + sampler
  descriptors.
- Record the frame into your command buffer with
  `imgui_backend_vulkan_render(handle, imgui_backend_draw_data(handle), cmd)`.
- A renderer backend is required for drawing; the platform-only selftest
  pairs SDL3 with the vendored null renderer.

Widgets/windows/tables wrappers and the GLFW backend remain Phase 3
(`ROADMAP.md`).

## Tests

```
scripts/port.ps1 -Package xiom.imgui
```

Expected: 11 `[PASS]`, exit 0. The suite drives real headless frames,
checks the long-lived context-handle lifecycle, runs the real SDL3 platform
backend against a hidden window (SKIP when the host has no video driver),
and verifies the Vulkan backend rejects missing engine handles without
crashing -- not only symbol resolution.
