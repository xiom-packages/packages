# xiom.imgui

Dear ImGui v1.92.9b bindings for XIOM. The upstream core and its headless
null backends are vendored into `vendor/` (MIT) and compiled into the test
binary with `--c-source` -- no precompiled objects, no SDK, no graphics
backend needed.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.3; 7/7). Published in `eco-v0.1.123` (sha256 `4d016de5...`).
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

Full details: `SPEC.md`; vendored provenance + per-file pin: `SPEC.md` §2.
Widgets/windows/tables wrappers and GLFW/Vulkan backends are Phase 3
(`ROADMAP.md`).

## Tests

```
scripts/port.ps1 -Package xiom.imgui
```

Expected: 7 `[PASS]`, exit 0. The suite drives real headless frames and
checks the tessellation output plus the long-lived context-handle lifecycle,
not only symbol resolution.
