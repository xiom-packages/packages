// XIOM — ImGui Production Showcase
// Menu bar, windows, tabs, trees, sliders, checkboxes,
// drags, color editors, plots, themes. Menu Exit or Escape to close.

module imgui_demo
use xiom.io;
use xiom.vulkan;
use xiom.imgui;

var g_app: Int = 0;
var g_fc: Int = 0;
var g_s1: Float32 = 0.0;
var g_s2: Int = 0;
var g_c1: Int = 0;
var g_c2: Int = 0;
var g_drag_f: Float32 = 0.0;
var g_drag_i: Int = 0;
var g_cr: Float32 = 0.0;
var g_cg: Float32 = 0.0;
var g_cb: Float32 = 0.0;
var g_if: Float32 = 0.0;

fn main() -> Int {
  let app = create_app("XIOM ImGui Showcase", 1280, 800);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_app = a;
      g_s1 = 0.65; g_s2 = 32;
      g_c1 = 1; g_c2 = 0;
      g_drag_f = 1.0; g_drag_i = 50;
      g_cr = 0.18; g_cg = 0.64; g_cb = 0.88;
      g_if = 0.0; g_fc = 0;

      let win  = unsafe { xvk_get_glfw_window(a) };
      let inst = unsafe { xvk_get_instance(a) };
      let dev  = unsafe { xvk_get_device(a) };
      let phys = unsafe { xvk_get_physical_device(a) };
      let q    = unsafe { xvk_get_graphics_queue(a) };
      let rp   = unsafe { xvk_get_render_pass(a) };

      if unsafe { imgui_bridge_init(win) } == 0 { destroy_app(a); return 1; }
      if unsafe { imgui_bridge_init_vulkan(inst, dev, phys, q, 0 as Int32, rp, 0 as Int32, 1280.0, 800.0) } == 0 {
        unsafe { imgui_bridge_shutdown(); }; destroy_app(a); return 1;
      }

      while !should_close(a) && g_fc < 10000 {
        if is_key_down(a, 256) { break; }
        poll(a);
        set_clear_color(a, 0.06, 0.06, 0.10);
        let status = begin_frame(a);
        if status == 1 {
          g_fc = g_fc + 1;
          unsafe { imgui_bridge_new_frame(); };

          // ── MENU BAR ──
          if unsafe { imgui_begin_menu_bar() } != 0 {
            if unsafe { imgui_begin_menu("File") } != 0 {
              if unsafe { imgui_menu_item("Exit", "Alt+F4", 1 as Int32) } != 0 { break; }
              unsafe { imgui_end_menu(); };
            }
            if unsafe { imgui_begin_menu("Theme") } != 0 {
              if unsafe { imgui_menu_item("Dark", "", 1 as Int32) } != 0 { unsafe { imgui_style_dark(); }; }
              if unsafe { imgui_menu_item("Light", "", 1 as Int32) } != 0 { unsafe { imgui_style_light(); }; }
              if unsafe { imgui_menu_item("Classic", "", 1 as Int32) } != 0 { unsafe { imgui_style_classic(); }; }
              unsafe { imgui_end_menu(); };
            }
            unsafe { imgui_end_menu_bar(); };
          }

          // ── WIDGET SHOWCASE ──
          unsafe { imgui_set_next_window_size(500.0, 520.0); };
          unsafe { imgui_set_next_window_pos(20.0, 30.0); };
          if unsafe { imgui_begin("Widgets", 0 as Int32) } != 0 {
            unsafe { imgui_text("Float Slider:"); };
            g_s1 = unsafe { imgui_slider_float("##s1", g_s1, 0.0, 1.0) };
            unsafe { imgui_text("Int Slider:"); };
            g_s2 = unsafe { imgui_slider_int("##s2", g_s2 as Int32, 0 as Int32, 100 as Int32) };
            unsafe { imgui_separator(); };
            g_c1 = unsafe { imgui_checkbox("Enable Rendering", g_c1) };
            g_c2 = unsafe { imgui_checkbox("Wireframe", g_c2) };
            unsafe { imgui_separator(); };
            unsafe { imgui_text("Drag controls:"); };
            g_drag_f = unsafe { imgui_drag_float("Scale", g_drag_f, 0.1, 0.0, 10.0) };
            g_drag_i = unsafe { imgui_drag_int("Count", g_drag_i, 1.0, 0 as Int32, 200 as Int32) };
            unsafe { imgui_separator(); };
            unsafe { imgui_text("Color:"); };
            unsafe { imgui_color_edit3("Pick", g_cr, g_cg, g_cb); };
            unsafe { imgui_separator(); };
            g_if = unsafe { imgui_input_float("Input", g_if) };
            unsafe { imgui_separator(); };
            if unsafe { imgui_button("Action") } != 0 {
              io.println("[imgui] Click!");
            }
            unsafe { imgui_same_line(0.0, 0.0); };
            if unsafe { imgui_small_button("?") } != 0 { }
            unsafe { imgui_end(); };
          }

          // ── TREE BROWSER ──
          unsafe { imgui_set_next_window_size(350.0, 300.0); };
          unsafe { imgui_set_next_window_pos(550.0, 30.0); };
          if unsafe { imgui_begin("Browser", 0 as Int32) } != 0 {
            if unsafe { imgui_collapsing_header("Meshes") } != 0 {
              if unsafe { imgui_tree_node("Cube") } != 0 {
                unsafe { imgui_text("  Verts: 24"); };
                unsafe { imgui_text("  Faces: 12"); };
                unsafe { imgui_tree_pop(); };
              }
              if unsafe { imgui_tree_node("Sphere") } != 0 {
                unsafe { imgui_text("  Verts: 128"); };
                unsafe { imgui_tree_pop(); };
              }
            }
            if unsafe { imgui_collapsing_header("Materials") } != 0 {
              if unsafe { imgui_tree_node("PBR Default") } != 0 {
                unsafe { imgui_text("  Albedo: 0.8"); };
                unsafe { imgui_tree_pop(); };
              }
            }
            unsafe { imgui_end(); };
          }

          // ── TABS ──
          unsafe { imgui_set_next_window_size(350.0, 200.0); };
          unsafe { imgui_set_next_window_pos(550.0, 360.0); };
          if unsafe { imgui_begin("Tabs", 0 as Int32) } != 0 {
            if unsafe { imgui_begin_tab_bar("TabBar") } != 0 {
              if unsafe { imgui_begin_tab_item("Settings") } != 0 {
                g_s1 = unsafe { imgui_slider_float("Value", g_s1, 0.0, 1.0) };
                g_c1 = unsafe { imgui_checkbox("Enabled", g_c1) };
                unsafe { imgui_end_tab_item(); };
              }
              if unsafe { imgui_begin_tab_item("Stats") } != 0 {
                unsafe { imgui_text("FPS: OK"); };
                unsafe { imgui_text("Draws: 5"); };
                unsafe { imgui_end_tab_item(); };
              }
              unsafe { imgui_end_tab_bar(); };
            }
            unsafe { imgui_end(); };
          }

          // ── STATUS BAR ──
          unsafe { imgui_set_next_window_size(400.0, 60.0); };
          unsafe { imgui_set_next_window_pos(20.0, 580.0); };
          if unsafe { imgui_begin("Status", 0 as Int32) } != 0 {
            unsafe { imgui_text("XIOM + ImGui v1.92.9"); };
            unsafe { imgui_same_line(0.0, 0.0); };
            unsafe { imgui_text("  |  Frame:"); };
            unsafe { imgui_end(); };
          }

          let cb = unsafe { xvk_get_command_buffer(a) };
          unsafe { imgui_bridge_render(cb); };
          end_frame(a);
        } elif status == -1 {
          io.println("ERROR: " + last_error()); break;
        }
      }

      unsafe { imgui_bridge_shutdown(); };
      destroy_app(a);
      io.println("[imgui] Done. Frames: OK");
      return 0;
    }
  }
}
