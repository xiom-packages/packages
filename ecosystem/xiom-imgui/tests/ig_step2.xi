// Step 2: Window + ImGui context only, no widgets — uses safe wrappers exclusively
module ig_test
use xiom.io;
use xiom.vulkan;
use xiom.imgui;

fn main() -> Int {
  let app = create_app("ImGui Test", 1280, 800);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      let win  = get_glfw_window(a);
      let inst = get_instance(a);
      let dev  = get_device(a);
      let phys = get_physical_device(a);
      let q    = get_graphics_queue(a);
      let rp   = get_render_pass(a);

      if !create_context(win) { destroy_app(a); return 1; }
      if !init_vulkan(inst, dev, phys, q, 0 as Int32, rp, 0 as Int32, 1280.0, 800.0) {
        destroy_context(); destroy_app(a); return 1;
      }

      var fc: Int = 0;
      while !should_close(a) && fc < 5000 {
        if is_key_down(a, 256) { break; }
        poll(a);
        set_clear_color(a, 0.06, 0.06, 0.10);
        let s = begin_frame(a);
        if s == 1 {
          fc = fc + 1;
          let fb_w = get_fb_width(a) as Int;
          let fb_h = get_fb_height(a) as Int;
          new_frame_sized(fb_w as Int32, fb_h as Int32);
          // No widgets - just new_frame + render
          let cb = get_command_buffer(a);
          render(cb);
          end_frame(a);
        } elif s == -1 { break; }
      }
      destroy_context();
      destroy_app(a);
      return 0;
    }
  }
}
