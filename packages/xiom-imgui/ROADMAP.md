# xiom.imgui -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot: 90 externs + precompiled bridge objects + GLFW/Vulkan backends (preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored headless core
- [x] Vendored flat core (4 sources + headers), per-file SHA256 pin
- [x] Integer-only bridge: version, headless frame, empty frame
- [x] Conformance suite (4 checks incl. tessellation determinism)

## Phase 3 (Done) -- 0.3.0 long-lived context handles
- [x] Context handle API (`imgui_context_create/frame/destroy`, <=4 live, registry) for long-lived frames
- [x] Side-effect-free runs (`io.IniFilename = 0`; the tracked imgui.ini artifact is gone)

## Phase 4 (Done) -- 0.4.0 SDL3 + Vulkan backends (engine-owned)
- [x] Vendored `imgui_impl_sdl3` + `imgui_impl_vulkan` (v1.92.9b) + SDL3/Vulkan-Headers trees + import libs (Vulkan SDK 1.4.350.0)
- [x] Backend handle registry: SDL3 platform attach (engine `SDL_Window`, event forwarding) + Vulkan renderer attach (engine instance/device/queue/pool/render pass)
- [x] `imgui_backend_frame` / `imgui_backend_draw_data` / `imgui_backend_vulkan_render` / shutdown
- [x] Real SDL3 selftest (hidden window) + typed missing-handle guards; 11/11 x2
- [x] 0.4.0 publish request

## Phase 5 (Next) -- UI surface + GLFW/dynamic-rendering follow-ups
- [ ] Widget wrappers (Button/InputText/Slider/Tree/TabBar/Menu)
- [ ] Tables + draw-list APIs
- [ ] Vulkan dynamic-rendering path (no render pass required)
- [ ] GLFW backend integration (vendored `imgui_impl_glfw` over `xiom.glfw`)
- [ ] `imgui_demo.cpp` vendored + example app
- [ ] Re-pin to the latest tag when the drift guard flags it
