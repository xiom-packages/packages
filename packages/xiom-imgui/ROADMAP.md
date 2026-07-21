# xiom-imgui — Production Roadmap

**Current rating: 6/10** — Good C bridge, incomplete XIOM coverage. Demo confirmed stable.
**C bridge**: 7 precompiled .obj files (Dear ImGui v1.92.9 + GLFW + Vulkan backends)
**XIOM layer**: Single 258-line module — 90 `extern "C"` declarations, 48 safe wrappers with contracts
**Demo**: 2-panel + menu + 3D viewport, confirmed stable for 6s+ at 1280x800
**Compiler**: xiomc v0.49.2 (798/798 tests)

---

## Honest Assessment

xiom-imgui wraps Dear ImGui v1.92.9 with a clean C ABI bridge. The bridge has been hardened: DisplaySize timing fixed, NewFrame order corrected (GLFW→Vulkan→ImGui), reinit_vulkan functional, color_edit3 read-back working, CheckVkResultFn registered, DPI font scale set, runtime version check added.

The XIOM layer (`imgui.xi`) has 48 safe wrappers with contracts — covering all commonly-used widgets. The demo is confirmed stable with 2 panels, menu bar, 3D viewport, and modal popup.

The remaining gaps are:
1. **Missing FFI declarations**: ~20 C bridge functions exist in the .h but have no `extern "C"` declaration in `imgui.xi` (combo, list_box, input_text, tooltips, plots, interaction queries)
2. **Missing safe wrappers**: Even when FFI exists, some functions lack safe wrappers (same_line with params, menu_item with shortcut — these exist but aren't used)
3. **Contract gaps**: No end/pop contracts for balanced Begin/End pairs
4. **Advanced features**: Tables, docking, font customization, texture display — deferred to v2
5. **No stdlib ffi usage**: Has inline `extern "C"` for all functions, should use `xiom.ffi` for malloc/free patterns

---

## Phase 1: Complete XIOM Coverage (6 → 7/10)

### IG-01: Add `extern "C"` declarations for ALL C bridge functions listed in AUDIT.md
**CRITICAL** | `imgui.xi`
20 functions exist in the C bridge but have NO XIOM declaration:
`input_float`, `input_int`, `input_text`, `color_edit4`, `combo`, `list_box`, `begin_disabled`, `end_disabled`, `tree_node_flags`, `begin_popup`, `end_popup`, `begin_popup_context_item`, `begin_menu_bar`, `end_menu_bar`, `set_tooltip`, `begin_tooltip`, `end_tooltip`, `set_scroll_here_y`, `is_item_hovered`, `is_item_clicked`, `push_style_color`, `pop_style_color`, `plot_lines`, `plot_histogram`, `get_frame_count`, `bridge_set_display_size_i32`

### IG-02: Add safe wrappers for all newly-declared FFI functions
**CRITICAL** | `imgui.xi`
Each wrapper needs:
- Bool return type (not Int32) where applicable
- Contract (`requires: label.len() > 0` where appropriate)
- Proper type mapping (Int→Float32, Bool→Int32 conversions)

### IG-03: Add paired-Begin/End state tracking contracts
**HIGH** | `imgui.xi`
Add `in_window: Bool`, `in_menu: Bool`, `in_tab: Bool`, `in_popup: Bool` state tracking via module-level vars. `end_window()` requires `in_window == true`.

### IG-04: Complete contract coverage for ALL safe wrappers
**HIGH** | `imgui.xi`
Currently only 9 functions have contracts. All 48+ should have appropriate `requires`.

---

## Phase 2: C Bridge Hardening (7 → 8/10)

### IG-05: Add input_text buffer management bridge
**HIGH** | `bridge/imgui_bridge.cpp`
`imgui_input_text` needs XIOM-side string buffer. Add `imgui_input_text_buf(label, buf_ptr, buf_size, out_len)` that writes back.

### IG-06: Add combo/list_box item array bridge
**MEDIUM** | `bridge/imgui_bridge.cpp`
Currently requires C-side `const char* const*` array. Need XIOM→C string array conversion helper.

### IG-07: Add plot data bridge
**MEDIUM** | `bridge/imgui_bridge.cpp`
`plot_lines`/`plot_histogram` need float array data. Add `imgui_plot_lines_f32(label, data_ptr, count, ...)`.

### IG-08: Fix `color_edit3_rgb` safe wrapper to return modified values
**MEDIUM** | `imgui.xi`
Current wrapper discards returned values. Add `color_edit3_get(r: &mut Float32, g: &mut Float32, b: &mut Float32)` that reads back.

### IG-09: Register GLFW content scale callback for DPI font scaling
**LOW** | `bridge/imgui_bridge.cpp`
Already have `io.FontGlobalScale` baseline. Add runtime update on DPI change.

---

## Phase 3: Ecosystem Integration (8 → 9/10)

### IG-10: Migrate to stdlib `xiom.ffi` for memory operations
**HIGH** | `imgui.xi`, `bridge/imgui_bridge.cpp`
Replace inline `extern "C"` malloc patterns with `use xiom.ffi;`.

### IG-11: Add `use xiom_ffi.buffer` for vertex/index data buffers
**LOW** | `demo_imgui.xi`, `imgui.xi`
Use `FFIBuffer` for ImGui vertex/index data management.

### IG-12: Move `imgui_bridge_new_frame_sized` to use `xiom.ffi` types
**LOW** | `imgui.xi`
`fb_w: Int32, fb_h: Int32` → could be `fb_w: UInt, fb_h: UInt` for consistency.

---

## Phase 4: Advanced Features (9 → 10/10)

### IG-13: Tables (`ImGui::BeginTable`/`EndTable`)
**Feature** | New bridge functions + XIOM wrappers
Requires struct marshalling for column configs. Deferred to v2.

### IG-14: Docking (`ImGuiConfigFlags_DockingEnable`)
**Feature** | `bridge/imgui_bridge.cpp`
Enable docking in ImGui config. Add dock space creation. Deferred to v2.

### IG-15: Font customization (TTF loading, atlas management)
**Feature** | `bridge/imgui_bridge.cpp`
Add `imgui_add_font_from_file_ttf(path, size_pixels)`. Deferred to v2.

### IG-16: Texture display (`ImGui::Image`)
**Feature** | `bridge/imgui_bridge.cpp`
Needs descriptor set management for ImGui image display. Deferred to v2.

### IG-17: Unit tests for all 48+ safe wrappers
**MEDIUM** | `tests/`
Only 1 CLI conformance test exists. Need tests for all widget functions (create/destroy context, begin/end window, button click, slider range, etc.).

### IG-18: Demo — full 4-panel layout with all widgets
**LOW** | `tests/demo_imgui.xi`
Current demo has 2 panels. Expand to full production layout once all Phase 1 safe wrappers exist.

### IG-19: Demo — sub-viewport 3D rendering (offscreen render → ImGui image)
**Feature** | `tests/demo_imgui.xi`
Use xvk offscreen render target, display result as ImGui image. Deferred to v2.

### IG-20: Performance benchmarks — frames-per-second overhead of safe wrappers
**LOW** | `tests/`

### IG-21: Error callback to XIOM — forward ImGui errors to `io.println`
**LOW** | `bridge/imgui_bridge.cpp`
Currently Vulkan errors go to stderr. Forward to XIOM runtime.

### IG-22: `package.xi` — add explicit `exports` field
**LOW** | `package.xi`

---

## Compiler/Stdlib Blockers

| Gap | Impact on xiom-imgui | Status |
|-----|---------------------|--------|
| CG-01b Int32→Float32 | `fb_w as Float32` division | Fixed v0.48.8 |
| CG-02 Float32 module init | `var g_*: Float32 = 0.5` | Fixed v0.48.6 |
| G-28 E001 moved value | All unsafe FFI calls trigger warnings | P2 non-fatal |
| `unknown type T` in imgui.xi generics | Safe wrapper `Bool`/`Result` types | Cosmetic, code works |
| `Drop` interface | Auto-cleanup of ImGui context | Not yet in compiler |
| `&mut Float32` | Needed for color_edit3 read-back without C pointers | Supported? Verify |
| `for` loops | Demo uses `while` — `for` would simplify iteration | Language limitation in v0.49.2 |
