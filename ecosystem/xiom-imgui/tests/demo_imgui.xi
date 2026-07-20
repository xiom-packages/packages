// XIOM — ImGui Production Demo (v0.49.2)
// Working baseline: 2 panels + menu bar. Window stable at 1280x800.
// TODO: add 3D viewport, status bar, tabs after verifying stability.

module imgui_demo
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
var g_frame : Int = 0;
var g_theme : Int = 0;

fn apply_theme(t: Int) {
  if t == 0 { style_dark(); }
  elif t == 1 { style_light(); }
  else { style_classic(); }
}

fn main() -> Int {
  let app = create_app("XIOM ImGui Demo", 1280, 800);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      let w = unsafe { xvk_get_glfw_window(a) };
      let i = unsafe { xvk_get_instance(a) };
      let d = unsafe { xvk_get_device(a) };
      let p = unsafe { xvk_get_physical_device(a) };
      let q = unsafe { xvk_get_graphics_queue(a) };
      let r = unsafe { xvk_get_render_pass(a) };

      if !create_context(w) { destroy_app(a); return 1; }
      if !init_vulkan(i, d, p, q, 0, r, 0, 1280.0, 800.0) {
        destroy_context(); destroy_app(a); return 1;
      }

      while !should_close(a) && g_frame < 100000 {
        if is_key_down(a, 256) { break; }
        poll(a);
        set_clear_color(a, 0.05, 0.05, 0.09);
        let status = begin_frame(a);
        if status == 1 {
          g_frame = g_frame + 1;

          let fb_w = unsafe { xvk_get_fb_width(a) };
          let fb_h = unsafe { xvk_get_fb_height(a) };
          unsafe { imgui_bridge_new_frame_sized(fb_w, fb_h); };

          let pad: Int = 8;
          let half: Int = (fb_w - pad * 3) / 2;
          let ch: Int = fb_h - pad * 2 - 20;

          // Menu bar
          if begin_main_menu_bar() {
            if begin_menu("File") {
              if menu_item("Exit") { break; }
              end_menu();
            }
            if begin_menu("Theme") {
              if menu_item("Dark") { g_theme = 0; apply_theme(0); }
              if menu_item("Light") { g_theme = 1; apply_theme(1); }
              if menu_item("Classic") { g_theme = 2; apply_theme(2); }
              end_menu();
            }
            end_main_menu_bar();
          }

          // Left: Widgets
          set_next_window_pos(pad, pad + 20);
          set_next_window_size(half, ch);
          if begin_window("Widgets", 0) {
            g_s_f = slider_float("Float", g_s_f, 0.0, 1.0);
            g_s_i = slider_int("Int", g_s_i, 0, 100);
            separator();
            g_c1 = if checkbox("Feature A", g_c1 != 0) { 1 } else { 0 };
            g_c2 = if checkbox("Feature B", g_c2 != 0) { 1 } else { 0 };
            g_c3 = if checkbox("Feature C", g_c3 != 0) { 1 } else { 0 };
            separator();
            if radio_button("Opt 1", g_radio == 0) { g_radio = 0; }
            same_line();
            if radio_button("Opt 2", g_radio == 1) { g_radio = 1; }
            same_line();
            if radio_button("Opt 3", g_radio == 2) { g_radio = 2; }
            separator();
            g_dragf = drag_float("Scale", g_dragf, 0.05, 0.0, 10.0);
            g_dragi = drag_int("Count", g_dragi, 1.0, 0, 200);
            end_window();
          }

          // Right: Info
          let bx: Int = pad * 2 + half;
          set_next_window_pos(bx, pad + 20);
          set_next_window_size(half, ch);
          if begin_window("Info", 0) {
            text("XIOM ImGui Demo v0.49.2");
            separator();
            text("Vulkan 1.3 + GLFW 3.4 + Dear ImGui v1.92.9");
            text("85+ wrapped functions with safe contracts");
            separator();
            text_wrapped("F11 fullscreen | drag resize | Escape or File>Exit to close");
            end_window();
          }

          let cb = unsafe { xvk_get_command_buffer(a) };
          render(cb);
          end_frame(a);
        } elif status == -1 {
          io.println("ERROR: " + last_error()); break;
        }
      }

      destroy_context();
      destroy_app(a);
      return 0;
    }
  }
}
