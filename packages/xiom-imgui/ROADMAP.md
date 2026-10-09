# xiom.imgui -- ROADMAP

## Phase 1 (Done) -- historical
- [x] 0.1.0 pre-pilot: 90 externs + precompiled bridge objects + GLFW/Vulkan backends (preserved in git history)

## Phase 2 (Done) -- 0.2.0 vendored headless core
- [x] Vendored flat core (4 sources + headers), per-file SHA256 pin
- [x] Integer-only bridge: version, headless frame, empty frame
- [x] Conformance suite (4 checks incl. tessellation determinism)

## Phase 3 (Planned)
- [ ] Context handle API (`imgui_context_create/destroy`) for long-lived frames
- [ ] Widget wrappers (Button/InputText/Slider/Tree/TabBar/Menu)
- [ ] Tables + draw-list APIs
- [ ] GLFW backend integration (vendored `imgui_impl_glfw` over `xiom.glfw`)
- [ ] Vulkan backend integration over `xiom.vulkan`
- [ ] `imgui_demo.cpp` vendored + example app
- [ ] Re-pin to the latest tag when the drift guard flags it
