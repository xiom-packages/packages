// XIOM — Minimal 2D test
module xiom.vulkan.demo2d_mini
use xiom.io;
use xiom.math;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Test", 800, 600);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      var n: Int = 0;
      while !should_close(a) {
        poll(a);
        let r = (math.sin(now()) * 0.5 + 0.5) as Float32;
        set_clear_color(a, 0.05, 0.05, 0.1);
        let status = begin_frame(a);
        if status == 1 {
          draw_triangle_2d(a, r, 0.3, 0.7);
          end_frame(a);
          n = n + 1;
          if n >= 120 { break; }
        } elif status == -1 { break; }
      }
      destroy_app(a);
      return 0;
    }
  }
}
