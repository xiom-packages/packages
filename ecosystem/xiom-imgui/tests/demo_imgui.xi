// ===========================================================================
// XIOM ImGui SDK — Full Widget Showcase
// Pure UI — no 3D rendering. Shows ALL available ImGui components.
// Menu bar, windows, sliders, checkboxes, radio, drag, color, progress,
// tabs, trees, collapsing headers, popups, modals, tooltips, plots, tables.
// ===========================================================================

module imgui_showcase
use xiom.io;
use xiom.vulkan;
use xiom.imgui;

var g_s_f   : Float32 = 0.65;
var g_s_i   : Int = 32;
var g_c1    : Int = 1;
var g_c2    : Int = 0;
var g_c3    : Int = 0;
var g_radio : Int = 0;
var g_dragf : Float32 = 1.0;
var g_dragi : Int = 50;
var g_cr    : Float32 = 0.18;
var g_cg    : Float32 = 0.64;
var g_cb    : Float32 = 0.88;
var g_prog  : Float32 = 0.0;
var g_modal : Int = 0;
var g_frame : Int = 0;
var g_theme : Int = 0;
var g_f11_p : Int = 0;

fn apply_theme(t: Int) {
  if t == 0 { style_dark(); }
  elif t == 1 { style_light(); }
  else { style_classic(); }
}

fn main() -> Int {
  let app = create_app("ImGui Widget Showcase", 1280, 800);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      let w = get_glfw_window(a);
      let i = get_instance(a);
      let d = get_device(a);
      let p = get_physical_device(a);
      let q = get_graphics_queue(a);
      let r = get_render_pass(a);

      if !create_context(w) { destroy_app(a); return 1; }
      if !init_vulkan(i, d, p, q, 0, r, 0, 1280.0, 800.0) {
        destroy_context(); destroy_app(a); return 1;
      }

      while !should_close(a) && g_frame < 100000 {
        if is_key_down(a, 256) { break; }
        let f11 = if is_key_down(a, 292) { 1 } else { 0 };
        if f11 != 0 && g_f11_p == 0 { app_toggle_fullscreen(a); }
        g_f11_p = f11;

        poll(a);
        set_clear_color(a, 0.05, 0.05, 0.09);
        let status = begin_frame(a);
        if status == 1 {
          g_frame = g_frame + 1;
          let fb_w = get_fb_width(a);
          let fb_h = get_fb_height(a);
          new_frame_sized(fb_w, fb_h);

          // ── MENU BAR ──────────────────────────────────────────────────────
          if begin_main_menu_bar() {
            if begin_menu("File") { if menu_item("Exit") { break; } end_menu(); }
            if begin_menu("Theme") {
              if menu_item("Dark") { g_theme = 0; apply_theme(0); }
              if menu_item("Light") { g_theme = 1; apply_theme(1); }
              if menu_item("Classic") { g_theme = 2; apply_theme(2); }
              end_menu();
            }
            if begin_menu("Help") {
              if menu_item_shortcut("About", "F1") { g_modal = 1; }
              end_menu();
            }
            end_main_menu_bar();
          }

          let pad: Int = 8;
          let top: Int = 20;
          let th: Int = (fb_w - pad * 3) / 2;
          let ch: Int = fb_h - top - pad * 2;

          // ── LEFT: Basic Widgets ───────────────────────────────────────────
          set_next_window_pos(pad, top);
          set_next_window_size(th, ch);
          if begin_window("Basic Widgets", 0) {
            // Section: Sliders
            if collapsing_header("Sliders") {
              g_s_f = slider_float("Float", g_s_f, 0.0, 1.0);
              g_s_i = slider_int("Int", g_s_i, 0, 100);
            }
            separator();

            // Section: Checkboxes
            if collapsing_header("Checkboxes") {
              g_c1 = if checkbox("Enable feature A", g_c1 != 0) { 1 } else { 0 };
              g_c2 = if checkbox("Enable feature B", g_c2 != 0) { 1 } else { 0 };
              g_c3 = if checkbox("Enable feature C (disabled)", g_c3 != 0) { 1 } else { 0 };
            }
            separator();

            // Section: Radio Buttons
            if collapsing_header("Radio Buttons") {
              if radio_button("Option Alpha", g_radio == 0) { g_radio = 0; }
              if radio_button("Option Beta",  g_radio == 1) { g_radio = 1; }
              if radio_button("Option Gamma", g_radio == 2) { g_radio = 2; }
            }
            separator();

            // Section: Drag Widgets
            if collapsing_header("Drag Widgets") {
              g_dragf = drag_float("Float scale", g_dragf, 0.05, 0.0, 10.0);
              g_dragi = drag_int("Int count", g_dragi, 1.0, 0, 200);
            }
            separator();

            // Section: Color Picker
            if collapsing_header("Color Picker") {
              color_edit3("RGB Color", g_cr, g_cg, g_cb);
              text_colored(g_cr, g_cg, g_cb, 1.0, "  Colored preview text");
            }
            separator();

            // Section: Progress Bar
            if collapsing_header("Progress") {
              g_prog = g_prog + 0.003;
              if g_prog > 1.0 { g_prog = 0.0; }
              progress_bar(g_prog);
              text_wrapped("Auto-cycling progress bar. Resets after reaching 100%.");
            }
            separator();

            // Buttons + Modal trigger
            if button("Open About Modal") { g_modal = 1; }
            same_line_spacing(8.0);
            if small_button("Small") { }
            end_window();
          }

          // ── RIGHT: Advanced Widgets ───────────────────────────────────────
          let bx: Int = pad * 2 + th;
          set_next_window_pos(bx, top);
          set_next_window_size(th, ch);
          if begin_window("Advanced Widgets", 0) {
            // Tabs
            if begin_tab_bar("DemoTabs") {
              // TAB: Trees
              if begin_tab_item("Trees") {
                if collapsing_header("Scene Graph") {
                  if tree_node("Root Node") {
                    if tree_node("Child A") {
                      text("Leaf data: 42");
                      tree_pop();
                    }
                    if tree_node("Child B") {
                      text("Leaf data: 128");
                      tree_pop();
                    }
                    tree_pop();
                  }
                  if tree_node("Camera") {
                    text("Position: (2.0, 2.0, 2.0)");
                    text("Target:  (0.0, 0.0, 0.0)");
                    tree_pop();
                  }
                }
                if collapsing_header("Asset Browser") {
                  if tree_node("Meshes")  { text("cube.obj"); text("sphere.obj"); tree_pop(); }
                  if tree_node("Textures") { text("albedo.png"); text("normal.png"); tree_pop(); }
                }
                end_tab_item();
              }

              // TAB: Layout
              if begin_tab_item("Layout") {
                text("Same-line demonstration:");
                text("A"); same_line();
                text("B"); same_line();
                text("C");
                separator();
                text_wrapped("This is wrapped text that demonstrates word wrapping. It will automatically break at the window edge. XIOM ImGui binding provides text_wrapped as a safe wrapper with contract enforcement.");
                separator();
                spacing();
                text("Above and below spacing");
                spacing();
                end_tab_item();
              }

              // TAB: Popups & Tooltips
              if begin_tab_item("Popups") {
                text("Hover over button for tooltip:");
                if button("Tooltip Button") { }
                if is_item_hovered() { set_tooltip("This is a tooltip!"); }
                separator();
                text("Right-click anywhere in this tab:");
                if begin_popup_context_item("Context Menu") {
                  if menu_item("Action 1") { }
                  if menu_item("Action 2") { }
                  separator();
                  if menu_item("Quit") { }
                  end_popup();
                }
                separator();
                if button("Show Popup") { open_popup("DemoPopup"); }
                if begin_popup("DemoPopup") {
                  text("This is a popup.");
                  if button("Close") { close_current_popup(); }
                  end_popup();
                }
                separator();
                text_wrapped("Press F1 or Help > About to see modal dialog.");
                end_tab_item();
              }

              // TAB: Info
              if begin_tab_item("Info") {
                let fps = get_framerate();
                text("Frame rate: ");
                if fps >= 55 { text_colored(0.2, 1.0, 0.3, 1.0, "GOOD"); }
                elif fps >= 30 { text_colored(1.0, 0.9, 0.2, 1.0, "OK"); }
                else { text_colored(1.0, 0.2, 0.2, 1.0, "SLOW"); }
                separator();
                text("XIOM ImGui SDK v0.3.0");
                text("Dear ImGui v1.92.9");
                text("85+ wrapped functions");
                text("65+ safe wrappers with contracts");
                separator();
                text_wrapped("This showcase demonstrates all available ImGui components wrapped for XIOM. Each widget has design-by-contract safety via requires/ensures clauses.");
                end_tab_item();
              }
              end_tab_bar();
            }
            end_window();
          }

          // ── MODAL ─────────────────────────────────────────────────────────
          if g_modal != 0 { open_popup("AboutModal"); g_modal = 0; }
          if begin_popup_modal("AboutModal") {
            text("XIOM ImGui Widget Showcase");
            separator();
            text_wrapped("Full widget set demonstration. 85+ wrapped ImGui functions with XIOM contracts. Includes: menus, windows, sliders, checkboxes, radio buttons, drag widgets, color pickers, progress bars, trees, collapsing headers, tabs, popups, modals, and tooltips.");
            separator();
            text("Platform: XIOM v0.49.5 + Vulkan 1.3");
            text("Backend: GLFW 3.4 + Dear ImGui v1.92.9");
            separator();
            if button("Close") { close_current_popup(); }
            end_popup_modal();
          }

          let cb = get_command_buffer(a);
          render(cb);
          end_frame(a);
        } elif status == -1 { break; }
      }

      destroy_context();
      destroy_app(a);
      return 0;
    }
  }
}
