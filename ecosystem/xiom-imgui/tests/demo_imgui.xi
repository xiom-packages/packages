// XIOM — ImGui Standalone Demo
// Verifies ImGui + Vulkan + GLFW integration.
// Press Escape or close window to exit.

module imgui_demo
use xiom.io;
use xiom.vulkan;
use xiom.imgui;

var g_app: Int = 0;
var g_slider_val: Float32 = 0.0;

fn main() -> Int {
  let app = create_app("XIOM ImGui Demo", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_app = a;
      g_slider_val = 0.5;

      // Init ImGui GLFW backend
      let win = unsafe { xvk_get_glfw_window(a) };
      if win == 0 {
        io.println("[imgui] Window handle is NULL!");
        destroy_app(a); return 1;
      }
      io.println("[imgui] Window handle OK");

      let raw = unsafe { imgui_bridge_init(win) };
      if raw == 0 {
        io.println("[imgui] Bridge init failed");
        destroy_app(a); return 1;
      }

      // Init ImGui Vulkan backend
      let inst  = unsafe { xvk_get_instance(a) };
      let dev   = unsafe { xvk_get_device(a) };
      let phys  = unsafe { xvk_get_physical_device(a) };
      let queue = unsafe { xvk_get_graphics_queue(a) };
      let rp    = unsafe { xvk_get_render_pass(a) };

      let raw_vk = unsafe { imgui_bridge_init_vulkan(inst, dev, phys, queue, 0 as Int32, rp, 0 as Int32, 1280.0, 720.0) };
      if raw_vk == 0 {
        io.println("[imgui] init_vulkan failed"); unsafe { imgui_bridge_shutdown(); }; destroy_app(a); return 1;
      }
      io.println("[imgui] Initialized OK. Press Escape to exit.");

      // Main loop
      while !should_close(a) {
        poll(a);
        let status = begin_frame(a);
        if status == 1 {
          set_clear_color(a, 0.04, 0.04, 0.06);
          imgui.new_frame();

          if imgui.begin_window("XIOM + ImGui v1.92.9") {
            imgui.text("Production ImGui window in XIOM!");
            imgui.spacing();
            imgui.separator();
            imgui.spacing();
            g_slider_val = imgui.slider_float("Slider", g_slider_val, 0.0, 1.0);
            let c = imgui.checkbox("Enable Feature", true);
            imgui.spacing();
            if imgui.button("Click Me!") { io.println("[imgui] Button clicked!"); }
          }
          imgui.end_window();

          let cb = unsafe { xvk_get_command_buffer(a) };
          imgui.render(cb);
          end_frame(a);

          if is_key_down(a, 256) { io.println("[imgui] Escape."); break; }
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
