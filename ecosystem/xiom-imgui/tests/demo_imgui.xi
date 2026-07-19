// XIOM — ImGui Production Demo
// Menu bar, windows, widgets. Stable.
// Menu File > Exit, Escape, or window X to close.

module imgui_demo
use xiom.io;
use xiom.vulkan;
use xiom.imgui;

var g_app: Int = 0;
var g_s_f: Float32 = 0.0;
var g_s_i: Int = 0;
var g_c1: Int = 0;
var g_c2: Int = 0;
var g_drag_f: Float32 = 0.0;
var g_drag_i: Int = 0;
var g_cr: Float32 = 0.0;
var g_cg: Float32 = 0.0;
var g_cb: Float32 = 0.0;
var g_show_modal: Int = 0;

fn main() -> Int {
  let app = create_app("XIOM ImGui Demo", 1280, 800);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_app = a;
      g_s_f = 0.65; g_s_i = 32; g_c1 = 1; g_c2 = 0;
      g_drag_f = 1.0; g_drag_i = 50;
      g_cr = 0.18; g_cg = 0.64; g_cb = 0.88;
      g_show_modal = 0;

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
          // Reinit ImGui Vulkan backend after swapchain resize
          if unsafe { xvk_app_did_resize(a) } != 0 {
            unsafe { xvk_app_clear_resize(a); };
            unsafe { imgui_bridge_reset_vulkan(inst, dev, phys, q, 0 as Int32, rp, 1280.0, 800.0); };
          }

          unsafe { imgui_bridge_new_frame(); };

          if unsafe { imgui_begin_main_menu_bar() } != 0 {
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
            unsafe { imgui_end_main_menu_bar(); };
          }

          unsafe { imgui_set_next_window_size(450.0, 300.0); };
          unsafe { imgui_set_next_window_pos(10.0, 30.0); };
          if unsafe { imgui_begin("Widgets", 0 as Int32) } != 0 {
            g_s_f = unsafe { imgui_slider_float("Float", g_s_f, 0.0, 1.0) };
            g_s_i = unsafe { imgui_slider_int("Int", g_s_i as Int32, 0 as Int32, 100 as Int32) };
            g_c1 = unsafe { imgui_checkbox("Feature A", g_c1) };
            g_c2 = unsafe { imgui_checkbox("Feature B", g_c2) };
            unsafe { imgui_separator(); };
            g_drag_f = unsafe { imgui_drag_float("Scale", g_drag_f, 0.1, 0.0, 10.0) };
            g_drag_i = unsafe { imgui_drag_int("Count", g_drag_i, 1.0, 0 as Int32, 200 as Int32) };
            unsafe { imgui_separator(); };
            unsafe { imgui_color_edit3("RGB", g_cr, g_cg, g_cb); };
            unsafe { imgui_separator(); };
            if unsafe { imgui_button("Open Modal") } != 0 { g_show_modal = 1; }
            unsafe { imgui_end(); };
          }

          if g_show_modal != 0 {
            unsafe { imgui_open_popup("MyModal"); };
            g_show_modal = 0;
          }
          if unsafe { imgui_begin_popup_modal("MyModal") } != 0 {
            unsafe { imgui_text("Modal window."); };
            if unsafe { imgui_button("Close") } != 0 { unsafe { imgui_close_current_popup(); }; }
            unsafe { imgui_end_popup_modal(); };
          }

          unsafe { imgui_set_next_window_size(300.0, 350.0); };
          unsafe { imgui_set_next_window_pos(480.0, 30.0); };
          if unsafe { imgui_begin("Browser", 0 as Int32) } != 0 {
            if unsafe { imgui_collapsing_header("Meshes") } != 0 {
              if unsafe { imgui_tree_node("Cube") } != 0 { unsafe { imgui_text("24 verts"); }; unsafe { imgui_tree_pop(); }; }
              if unsafe { imgui_tree_node("Sphere") } != 0 { unsafe { imgui_text("128 verts"); }; unsafe { imgui_tree_pop(); }; }
            }
            unsafe { imgui_end(); };
          }

          unsafe { imgui_set_next_window_size(300.0, 160.0); };
          unsafe { imgui_set_next_window_pos(480.0, 410.0); };
          if unsafe { imgui_begin("Tabs", 0 as Int32) } != 0 {
            if unsafe { imgui_begin_tab_bar("T") } != 0 {
              if unsafe { imgui_begin_tab_item("Settings") } != 0 {
                g_s_f = unsafe { imgui_slider_float("Vol", g_s_f, 0.0, 1.0) };
                unsafe { imgui_end_tab_item(); };
              }
              if unsafe { imgui_begin_tab_item("Info") } != 0 {
                unsafe { imgui_text("v1.92.9"); };
                unsafe { imgui_end_tab_item(); };
              }
              unsafe { imgui_end_tab_bar(); };
            }
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
      return 0;
    }
  }
}
