# xiom.imgui

Dear ImGui v1.92.9b bindings for XIOM. The upstream core and its headless
null backends are vendored into `vendor/` (MIT) and compiled into the test
binary with `--c-source` -- no precompiled objects, no SDK, no graphics
backend needed.

> **Status:** `incubating` -- conformance suite green on the pin (xiom
> v0.64.2; 4/4). **Lane:** bindings (`keywords: ["binding"]`).

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

Full details: `SPEC.md`; vendored provenance + per-file pin: `SPEC.md` §2.
Widgets/windows/tables wrappers and GLFW/Vulkan backends are Phase 2
(`ROADMAP.md`).

## Tests

```
scripts/port.ps1 -Package xiom.imgui
```

Expected: 4 `[PASS]`, exit 0. The suite drives real headless frames and
checks the tessellation output, not only symbol resolution.
