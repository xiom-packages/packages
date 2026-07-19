// XIOM — ImGui Production Demo
// Full interactive ImGui window with widgets.
// Press Escape or close window to exit.
module imgui_demo

use xiom.io;
use xiom.vulkan;
use xiom.imgui;

var g_app: Int = 0;
var g_counter: Int = 0;
var g_slider_f: Float32 = 0.0;
var g_check: Int = 0;

fn main() -> Int {
  let app = create_app("XIOM ImGui Demo", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_app = a;
      g_slider_f = 0.5; g_check = 1;

      let win  = unsafe { xvk_get_glfw_window(a) };
      let inst = unsafe { xvk_get_instance(a) };
      let dev  = unsafe { xvk_get_device(a) };
      let phys = unsafe { xvk_get_physical_device(a) };
      let q    = unsafe { xvk_get_graphics_queue(a) };
      let rp   = unsafe { xvk_get_render_pass(a) };

      if unsafe { imgui_bridge_init(win) } == 0 { io.println("GLFW init fail"); destroy_app(a); return 1; }
      if unsafe { imgui_bridge_init_vulkan(inst, dev, phys, q, 0 as Int32, rp, 0 as Int32, 1280.0, 720.0) } == 0 {
        io.println("VK init fail"); unsafe { imgui_bridge_shutdown(); }; destroy_app(a); return 1;
      }
      io.println("[imgui] Ready. Press Escape to exit.");

      while !should_close(a) {
        poll(a);
        set_clear_color(a, 0.06, 0.06, 0.10);
        let status = begin_frame(a);
        if status == 1 {
          unsafe { imgui_bridge_new_frame(); };

          // Main window
          if unsafe { imgui_begin("XIOM + Dear ImGui v1.92.9", 0 as Int32) } != 0 {
            unsafe { imgui_text("Production ImGui demo in XIOM!"); };
            unsafe { imgui_separator(); };
            unsafe { imgui_spacing(); };

            unsafe { imgui_text("This demo uses the full ImGui C API."); };
            unsafe { imgui_text("Sliders, checkboxes, buttons, trees, tabs."); };
            unsafe { imgui_spacing(); };

            g_slider_f = unsafe { imgui_slider_float("Float Slider", g_slider_f, 0.0, 1.0) };
            g_check = unsafe { imgui_checkbox("Enable Feature", g_check) };
            unsafe { imgui_spacing(); };

            if unsafe { imgui_button("Click Me!") } != 0 {
              g_counter = g_counter + 1;
            }
            unsafe { imgui_same_line(0.0, 0.0); };
            unsafe { imgui_text("Clicks:"); };

            unsafe { imgui_separator(); };
            if unsafe { imgui_collapsing_header("Advanced") } != 0 {
              unsafe { imgui_text("Frame time: ~16.6 ms"); };
              unsafe { imgui_text("GPU: NVIDIA GeForce RTX 3070 Ti"); };
              if unsafe { imgui_tree_node("Vertex Data") } != 0 {
                unsafe { imgui_text("Position: 4 bytes/vert"); };
                unsafe { imgui_text("Color: 4 bytes/vert"); };
                unsafe { imgui_tree_pop(); };
              }
            }
            unsafe { imgui_end(); };
          }

          // Second window — always show
          unsafe { imgui_set_next_window_size(300.0, 150.0); };
          unsafe { imgui_set_next_window_pos(700.0, 50.0); };
          if unsafe { imgui_begin("Performance", 0 as Int32) } != 0 {
            unsafe { imgui_text("Draw calls: 2"); };
            unsafe { imgui_text("Vertices: 8"); };
            unsafe { imgui_text("Indices: 12"); };
            let fps = unsafe { imgui_get_framerate() };
            unsafe { imgui_text("FPS: OK"); };
            unsafe { imgui_end(); };
          }

          let cb = unsafe { xvk_get_command_buffer(a) };
          unsafe { imgui_bridge_render(cb); };
          end_frame(a);
          if is_key_down(a, 256) { break; }
        } elif status == -1 { io.println("ERROR: " + last_error()); break; }
      }

      unsafe { imgui_bridge_shutdown(); };
      destroy_app(a);
      return 0;
    }
  }
}
