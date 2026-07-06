// XIOM — Vulkan 2D Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates the 2D triangle drawing API with cycling colors.
module xiom.vulkan.demo2d

use xiom.io;
use xiom.math;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Vulkan 2D", 800, 600);
  match app {
    Err(e) => {
      io.println(e);
      return 1;
    },
    Ok(a) => {
      while !should_close(a) {
        poll(a);
        let status = begin_frame(a);
        if status == 1 {
          let t = now();
          let r = (math.sin(t) * 0.5 + 0.5) as Float32;
          let g = (math.sin(t + 2.0) * 0.5 + 0.5) as Float32;
          let b = (math.sin(t + 4.0) * 0.5 + 0.5) as Float32;
          set_clear_color(a, 0.1, 0.1, 0.15);
          draw_triangle_2d(a, r, g, b);
          end_frame(a);
        } elif status == -1 {
          break;
        }
      }
      destroy_app(a);
      return 0;
    },
  }
}
