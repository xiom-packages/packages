// ===========================================================================
// XIOM Vulkan SDK — Example 01: First Triangle
// xiomc demo_01_triangle.xi --release --c-source ../bridge/xvk_bridge.obj
// ===========================================================================

module demo_triangle
use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("01 — First Triangle", 800, 600);
  match app {
    Err(e) => { return 1; }
    Ok(a) => {
      var hue: Float32 = 0.0;
      while !should_close(a) {
        if is_key_down(a, 256) { break; }
        poll(a);
        // Dynamic clear color cycles through purple-blue hues
        let r: Float32 = 0.1 + 0.05 * hue;
        let g: Float32 = 0.05;
        let b: Float32 = 0.2 + 0.1 * hue;
        set_clear_color(a, r, g, b);
        hue = hue + 0.005;
        if hue > 1.0 { hue = 0.0; }

        let status = begin_frame(a);
        if status == 1 {
          draw_triangle_2d(a, 0.9, 0.2, 0.5);  // orange triangle
          end_frame(a);
        } elif status == -1 { break; }
      }
      destroy_app(a);
      return 0;
    }
  }
}
