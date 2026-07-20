# xiom-imgui — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: CRITICAL
**Status**: PRODUCTION — v0.3.0, 90+ FFI, 65+ safe wrappers, Begin/End tracking
**Depends on**: xiom.ffi (stdlib), xiom-vulkan, xiom-glfw

## What it wraps
Dear ImGui v1.92.9 — immediate-mode GUI library.
Widgets, windows, tabs, popups, menus, plots, styling.

## Dependencies

| What | How | Size |
|------|-----|------|
| Dear ImGui v1.92.9 | **Bundled as .obj** (7 files: imgui, draw, widgets, tables, impl_glfw, impl_vulkan, bridge) | ~500KB source |
| GLFW 3.4 | System-installed (via xiom-glfw) | — |
| Vulkan SDK | System-installed (via xiom-vulkan) | — |

## Bundling strategy
**Dear ImGui bundled only.** It's small (~500KB) and has no package manager.
All other deps (GLFW, Vulkan) are system-installed via their respective packages.

## Architecture
```
xiom-imgui/
├── imgui.xi              # 90+ FFI declarations, 65+ safe wrappers
├── bridge/
│   ├── imgui_bridge.*    # C ABI wrapper (76 functions)
│   ├── imgui_impl_glfw.* # GLFW backend
│   ├── imgui_impl_vulkan.* # Vulkan backend
│   └── *.obj             # 7 pre-compiled
└── tests/
    ├── demo_imgui.xi     # Verified: 5s stable, 3D viewport
    ├── test_imgui.xi     # CLI conformance
    └── integration_test.xi # GLFW+Vulkan verified
```

## API (key functions, all with contracts)

```xiom
// Lifecycle
pub fn create_context(win) -> Bool
pub fn destroy_context()
pub fn init_vulkan(inst,dev,phys,q,family,rp,subpass,w,h) -> Bool
pub fn render(cb)

// Windows
pub fn begin_window(title, flags) -> Bool  // requires: g_win_open == 0
pub fn end_window()                         // requires: g_win_open == 1

// State tracking (Sprint 4)
var g_win_open   // begin_window/end_window pairing guard
var g_menu_open  // begin_menu/end_menu
var g_tab_bar    // begin_tab_bar/end_tab_bar
var g_tab_item   // begin_tab_item/end_tab_item
var g_popup_open // begin_popup_modal/end_popup_modal
var g_tree_level // tree_node/tree_pop (nesting allowed)

// All wrapper functions (65 total)
```

## Verified
- ImGui demo: 5s stable ✅ (v0.49.5)
- 3D viewport with rotating cube ✅
- Theme switching (Dark/Light/Classic) ✅
- F11 fullscreen toggle ✅
- Modal popups ✅
