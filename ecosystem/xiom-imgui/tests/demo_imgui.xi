// XIOM — ImGui Demo (v0.49.2, proper safe wrappers)
// Uses xiom.vulkan + xiom.imgui with design-by-contract.
// Minimal test confirmed vulkan works. ImGui bridge is the integration layer.
module imgui_demo
use xiom.io;
use xiom.vulkan;
use xiom.imgui;

var g_s_f: Float32 = 0.65;
var g_radio: Int = 0;
var g_frame: Int = 0;

fn main() -> Int {
  let app = create_app("XIOM ImGui Demo", 1280, 800);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      let w = unsafe { xvk_get_glfw_window(a) };
      let inst = unsafe { xvk_get_instance(a) };
      let dev  = unsafe { xvk_get_device(a) };
      let phys = unsafe { xvk_get_physical_device(a) };
      let q    = unsafe { xvk_get_graphics_queue(a) };
      let rp   = unsafe { xvk_get_render_pass(a) };

      if !create_context(w) { destroy_app(a); return 1; }
      if !init_vulkan(inst, dev, phys, q, 0, rp, 0, 1280.0, 800.0) {
        destroy_context(); destroy_app(a); return 1;
      }

      while !should_close(a) && g_frame < 100000 {
        poll(a);
        set_clear_color(a, 0.05, 0.05, 0.09);
        let status = begin_frame(a);
        if status == 1 {
          g_frame = g_frame + 1;

          let fb_w = unsafe { xvk_get_fb_width(a) };
          let fb_h = unsafe { xvk_get_fb_height(a) };
          unsafe { imgui_bridge_new_frame_sized(fb_w, fb_h); };

          set_next_window_pos(8, 20);
          set_next_window_size(300, 200);
          if begin_window("Hello", 0) {
            g_s_f = slider_float("Slider", g_s_f, 0.0, 1.0);
            if button("Click me") { io.println("clicked"); }
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
