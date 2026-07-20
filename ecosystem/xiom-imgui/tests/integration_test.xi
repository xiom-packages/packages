module integration_test
use xiom.glwf;
use xiom.vulkan;

fn main() -> Int {
  if !xiom.glwf.glfw_init() { return 1; }
  let win = xiom.glwf.glfw_create_window("GLFW+Vulkan", 800, 600);
  match win {
    Err(e) => { xiom.glwf.glfw_terminate(); return 1; }
    Ok(w) => {
      let app = create_app_from_window(w, 800, 600);
      match app {
        Err(e) => { xiom.glwf.glfw_destroy_window(w); xiom.glwf.glfw_terminate(); return 1; }
        Ok(a) => {
          while !xiom.glwf.glfw_should_close(w) && !should_close(a) {
            xiom.glwf.glfw_poll_events();
            set_clear_color(a, 0.1, 0.1, 0.2);
            let status = begin_frame(a);
            if status == 1 {
              draw_triangle_2d(a, 0.8, 0.2, 0.2);
              end_frame(a);
            }
          }
          destroy_app(a);
        }
      }
      xiom.glwf.glfw_destroy_window(w);
    }
  }
  xiom.glwf.glfw_terminate();
  return 0;
}
