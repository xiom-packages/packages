// XIOM — ImGui Production Showcase
// Every supported ImGui component demonstrated.
// Menu File > Exit, Theme > Dark/Light/Classic, or Escape to close.

module imgui_demo
use xiom.io;
use xiom.vulkan;
use xiom.imgui;

var g_app: Int = 0;
var g_fc: Int = 0;
var g_s_f: Float32 = 0.0;
var g_s_i: Int = 0;
var g_c1: Int = 0;
var g_c2: Int = 0;
var g_drag_f: Float32 = 0.0;
var g_drag_i: Int = 0;
var g_cr: Float32 = 0.0;
var g_cg: Float32 = 0.0;
var g_cb: Float32 = 0.0;
var g_ca: Float32 = 0.0;
var g_if: Float32 = 0.0;

fn main() -> Int {
  let app = create_app("XIOM ImGui Showcase — All Widgets", 1280, 800);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_app = a;
      g_s_f = 0.65; g_s_i = 32; g_c1 = 1; g_c2 = 0;
      g_drag_f = 1.0; g_drag_i = 50;
      g_cr = 0.18; g_cg = 0.64; g_cb = 0.88; g_ca = 1.0;
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

      while !should_close(a) {
        if is_key_down(a, 256) { break; }
        poll(a);
        set_clear_color(a, 0.06, 0.06, 0.10);
        let status = begin_frame(a);
        if status == 1 {
          g_fc = g_fc + 1;
          unsafe { imgui_bridge_new_frame(); };

          // ══════════════ MENU BAR ══════════════
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

          // ══════════════ BASIC WIDGETS ══════════════
          unsafe { imgui_set_next_window_size(420.0, 400.0); };
          unsafe { imgui_set_next_window_pos(10.0, 30.0); };
          if unsafe { imgui_begin("Basic Widgets", 0 as Int32) } != 0 {
            unsafe { imgui_text("Sliders:"); };
            g_s_f = unsafe { imgui_slider_float("Float", g_s_f, 0.0, 1.0) };
            g_s_i = unsafe { imgui_slider_int("Int", g_s_i as Int32, 0 as Int32, 100 as Int32) };
            unsafe { imgui_separator(); };

            unsafe { imgui_text("Checkboxes:"); };
            g_c1 = unsafe { imgui_checkbox("Enable Feature", g_c1) };
            if g_c1 != 0 {
              unsafe { imgui_same_line(0.0, 0.0); };
              g_c2 = unsafe { imgui_checkbox("Sub-option", g_c2) };
            }
            unsafe { imgui_separator(); };

            unsafe { imgui_text("Drag controls:"); };
            g_drag_f = unsafe { imgui_drag_float("Scale", g_drag_f, 0.1, 0.0, 10.0) };
            g_drag_i = unsafe { imgui_drag_int("Count", g_drag_i, 1.0, 0 as Int32, 200 as Int32) };
            unsafe { imgui_separator(); };

            unsafe { imgui_text("Color pickers:"); };
            unsafe { imgui_color_edit3("RGB", g_cr, g_cg, g_cb); };
            unsafe { imgui_color_edit4("RGBA", g_cr, g_cg, g_cb, g_ca); };
            unsafe { imgui_separator(); };

            unsafe { imgui_text("Input:"); };
            g_if = unsafe { imgui_input_float("Value", g_if) };
            unsafe { imgui_separator(); };

            unsafe { imgui_text("Buttons:"); };
            if unsafe { imgui_button("Primary") } != 0 { io.println("Primary"); }
            unsafe { imgui_same_line(0.0, 0.0); };
            if unsafe { imgui_small_button("?") } != 0 { io.println("Help"); }
            unsafe { imgui_end(); };
          }

          // ══════════════ TREES + COLLAPSING ══════════════
          unsafe { imgui_set_next_window_size(300.0, 400.0); };
          unsafe { imgui_set_next_window_pos(450.0, 30.0); };
          if unsafe { imgui_begin("Trees & Headers", 0 as Int32) } != 0 {
            if unsafe { imgui_collapsing_header("Meshes") } != 0 {
              if unsafe { imgui_tree_node("Cube") } != 0 {
                unsafe { imgui_text("Verts: 24"); };
                unsafe { imgui_text("Faces: 12"); };
                unsafe { imgui_tree_pop(); };
              }
              if unsafe { imgui_tree_node("Sphere") } != 0 {
                unsafe { imgui_text("Verts: 128"); };
                unsafe { imgui_tree_pop(); };
              }
            }
            if unsafe { imgui_collapsing_header("Materials") } != 0 {
              if unsafe { imgui_tree_node("PBR Default") } != 0 {
                unsafe { imgui_text("Albedo: 0.8"); };
                unsafe { imgui_tree_pop(); };
              }
              if unsafe { imgui_tree_node("Emissive") } != 0 {
                unsafe { imgui_text("Color: (1,0.5,0)"); };
                unsafe { imgui_tree_pop(); };
              }
            }
            if unsafe { imgui_collapsing_header("Textures") } != 0 {
              if unsafe { imgui_tree_node("Diffuse") } != 0 { unsafe { imgui_tree_pop(); }; }
              if unsafe { imgui_tree_node("Normal") } != 0 { unsafe { imgui_tree_pop(); }; }
              if unsafe { imgui_tree_node("Roughness") } != 0 { unsafe { imgui_tree_pop(); }; }
            }
            unsafe { imgui_end(); };
          }

          // ══════════════ TABS ══════════════
          unsafe { imgui_set_next_window_size(300.0, 200.0); };
          unsafe { imgui_set_next_window_pos(770.0, 30.0); };
          if unsafe { imgui_begin("Tabs", 0 as Int32) } != 0 {
            if unsafe { imgui_begin_tab_bar("MainTabs") } != 0 {
              if unsafe { imgui_begin_tab_item("Settings") } != 0 {
                g_s_f = unsafe { imgui_slider_float("Volume", g_s_f, 0.0, 1.0) };
                g_c1 = unsafe { imgui_checkbox("Mute", g_c1) };
                unsafe { imgui_end_tab_item(); };
              }
              if unsafe { imgui_begin_tab_item("Display") } != 0 {
                unsafe { imgui_color_edit3("Tint", g_cr, g_cg, g_cb); };
                unsafe { imgui_end_tab_item(); };
              }
              if unsafe { imgui_begin_tab_item("About") } != 0 {
                unsafe { imgui_text("XIOM + ImGui v1.92.9"); };
                unsafe { imgui_end_tab_item(); };
              }
              unsafe { imgui_end_tab_bar(); };
            }
            unsafe { imgui_end(); };
          }

          // ══════════════ POPUP + TOOLTIP ══════════════
          unsafe { imgui_set_next_window_size(300.0, 130.0); };
          unsafe { imgui_set_next_window_pos(770.0, 260.0); };
          if unsafe { imgui_begin("Popups", 0 as Int32) } != 0 {
            if unsafe { imgui_button("Open Popup") } != 0 {
              unsafe { imgui_open_popup("TestPopup"); };
            }
            if unsafe { imgui_begin_popup("TestPopup") } != 0 {
              unsafe { imgui_text("Popup content here!"); };
              unsafe { imgui_separator(); };
              if unsafe { imgui_button("Close") } != 0 {
                unsafe { imgui_close_current_popup(); };
              }
              unsafe { imgui_end_popup(); };
            }
            unsafe { imgui_separator(); };
            unsafe { imgui_text("Right-click the button above"); };
            unsafe { imgui_end(); };
          }

          // ══════════════ PLOTS ══════════════
          unsafe { imgui_set_next_window_size(400.0, 150.0); };
          unsafe { imgui_set_next_window_pos(10.0, 460.0); };
          if unsafe { imgui_begin("Performance Plots", 0 as Int32) } != 0 {
            let plot_buf = unsafe { xvk_alloc(16 * 4) };
            if plot_buf != 0 {
              unsafe { imgui_plot_lines("Frame", plot_buf, 16 as Int32, 0.0, 1.0, 370.0, 60.0); };
              unsafe { xvk_free(plot_buf); };
            }
            unsafe { imgui_text("FPS: OK"); };
            unsafe { imgui_text("GPU: NVIDIA RTX 3070 Ti"); };
            unsafe { imgui_end(); };
          }

          // ══════════════ STATUS BAR ══════════════
          unsafe { imgui_set_next_window_size(500.0, 50.0); };
          unsafe { imgui_set_next_window_pos(10.0, 640.0); };
          if unsafe { imgui_begin("Status", 0 as Int32) } != 0 {
            unsafe { imgui_text("XIOM + Dear ImGui v1.92.9"); };
            unsafe { imgui_same_line(0.0, 0.0); };
            unsafe { imgui_text("|  DPI auto-scaled"); };
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
      io.println("[imgui] Done.");
      return 0;
    }
  }
}
