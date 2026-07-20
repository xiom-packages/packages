// Minimal test: window only, no ImGui. 
// Tests resize stability.
module min_test
use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("Minimal Test", 1280, 800);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      var fc: Int = 0;
      while !should_close(a) && fc < 5000 {
        if is_key_down(a, 256) { break; }
        poll(a);
        set_clear_color(a, 0.06, 0.06, 0.10);
        let s = begin_frame(a);
        if s == 1 {
          fc = fc + 1;
          end_frame(a);
        } elif s == -1 { io.println("ERROR"); break; }
      }
      destroy_app(a);
      return 0;
    }
  }
}
