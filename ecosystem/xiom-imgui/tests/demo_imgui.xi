// XIOM — ImGui Production Demo (Fluid Layout, v0.48.6)
// Windows sized relative to framebuffer using integer math.
// Scales from 720p to 4K. Menu File > Exit, Escape, or X to close.

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
var g_frame: Int = 0;

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
      g_frame = 0;

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

      // Maximize window on startup
      unsafe { xvk_app_maximize(a); };

      while !should_close(a) && g_frame < 100000 {
        if is_key_down(a, 256) { break; }
        if is_key_down(a, 292) { unsafe { xvk_app_toggle_fullscreen(a); }; }  // F11
        poll(a);
        set_clear_color(a, 0.06, 0.06, 0.10);
        let status = begin_frame(a);
        if status == 1 {
          g_frame = g_frame + 1;
          let fb_w = unsafe { xvk_get_fb_width(a) } as Int;
          let fb_h = unsafe { xvk_get_fb_height(a) } as Int;
          unsafe { imgui_bridge_new_frame_sized(fb_w as Int32, fb_h as Int32); };

          // Fluid layout: 3 columns + bottom status bar
          let pad: Int = 8;
          let sbh: Int = 28;
          let third: Int = (fb_w - pad * 4) / 3;
          let content_h: Int = fb_h - sbh - 32;

          // ── MENU ──
          if unsafe { imgui_begin_main_menu_bar() } != 0 {
            if unsafe { imgui_begin_menu("File") } != 0 {
              if unsafe { imgui_menu_item("Exit", "Alt+F4", 1 as Int32) } != 0 { break; }
              unsafe { imgui_end_menu(); };
            }
            unsafe { imgui_end_main_menu_bar(); };
          }

          // ── WIDGETS ──
          unsafe { imgui_set_next_window_pos_i32(pad as Int32, 20 as Int32); };
          unsafe { imgui_set_next_window_size_i32(third as Int32, content_h as Int32); };
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

          // ── BROWSER ──
          let bx: Int = pad * 2 + third;
          unsafe { imgui_set_next_window_pos_i32(bx as Int32, 20 as Int32); };
          unsafe { imgui_set_next_window_size_i32(third as Int32, content_h as Int32); };
          if unsafe { imgui_begin("Browser", 0 as Int32) } != 0 {
            if unsafe { imgui_collapsing_header("Meshes") } != 0 {
              if unsafe { imgui_tree_node("Cube") } != 0 { unsafe { imgui_text("24 verts"); }; unsafe { imgui_tree_pop(); }; }
              if unsafe { imgui_tree_node("Sphere") } != 0 { unsafe { imgui_text("128 verts"); }; unsafe { imgui_tree_pop(); }; }
            }
            if unsafe { imgui_collapsing_header("Textures") } != 0 {
              if unsafe { imgui_tree_node("Diffuse") } != 0 { unsafe { imgui_tree_pop(); }; }
              if unsafe { imgui_tree_node("Normal") } != 0 { unsafe { imgui_tree_pop(); }; }
            }
            unsafe { imgui_end(); };
          }

          // ── TABS ──
          let tx: Int = pad * 3 + third * 2;
          unsafe { imgui_set_next_window_pos_i32(tx as Int32, 20 as Int32); };
          unsafe { imgui_set_next_window_size_i32(third as Int32, (fb_h / 2) as Int32); };
          if unsafe { imgui_begin("Tabs", 0 as Int32) } != 0 {
            if unsafe { imgui_begin_tab_bar("T") } != 0 {
              if unsafe { imgui_begin_tab_item("Settings") } != 0 {
                g_s_f = unsafe { imgui_slider_float("Vol", g_s_f, 0.0, 1.0) };
                unsafe { imgui_end_tab_item(); };
              }
              if unsafe { imgui_begin_tab_item("Info") } != 0 {
                unsafe { imgui_text("XIOM v0.48.6"); };
                unsafe { imgui_end_tab_item(); };
              }
              unsafe { imgui_end_tab_bar(); };
            }
            unsafe { imgui_end(); };
          }

          // ── STATUS ──
          unsafe { imgui_set_next_window_pos_i32(0 as Int32, (fb_h - sbh) as Int32); };
          unsafe { imgui_set_next_window_size_i32(fb_w as Int32, sbh as Int32); };
          if unsafe { imgui_begin("Status", 0 as Int32) } != 0 {
            unsafe { imgui_text("XIOM v0.48.6 | Dear ImGui v1.92.9 | Fluid"); };
            unsafe { imgui_end(); };
          }

          // ── MODAL ──
          if g_show_modal != 0 { unsafe { imgui_open_popup("MyModal"); }; g_show_modal = 0; }
          if unsafe { imgui_begin_popup_modal("MyModal") } != 0 {
            unsafe { imgui_text("Modal window."); };
            if unsafe { imgui_button("Close") } != 0 { unsafe { imgui_close_current_popup(); }; }
            unsafe { imgui_end_popup_modal(); };
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
