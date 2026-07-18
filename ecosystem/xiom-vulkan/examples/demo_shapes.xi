// XIOM — Vulkan 2D Shapes Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates the 2D quad and triangle drawing APIs with animation.
module xiom.vulkan.demo_shapes

use xiom.io;
use xiom.math;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Vulkan — 2D Shapes", 800, 600);
  match app {
    Err(e) => {
      io.println(e);
      return 1;
    }
    Ok(a) => {
      while !should_close(a) {
        poll(a);
        let t = now();
        set_clear_color(a, 0.05, 0.05, 0.1);
        let status = begin_frame(a);
        if status == 1 {
          // Quad 1 — red, orbits center
          let c1x = (math.sin(t) * 0.6) as Float32;
          let c1y = (math.cos(t) * 0.6) as Float32;
          draw_quad_2d(a, c1x, c1y, 0.12, 0.12, 1.0, 0.2, 0.2);
          // Quad 2 — green, 120° phase offset
          let c2x = (math.sin(t + 2.094) * 0.6) as Float32;
          let c2y = (math.cos(t + 2.094) * 0.6) as Float32;
          draw_quad_2d(a, c2x, c2y, 0.12, 0.12, 0.2, 1.0, 0.2);
          // Quad 3 — blue, 240° phase offset
          let c3x = (math.sin(t + 4.189) * 0.6) as Float32;
          let c3y = (math.cos(t + 4.189) * 0.6) as Float32;
          draw_quad_2d(a, c3x, c3y, 0.12, 0.12, 0.2, 0.2, 1.0);
          // Quad 4 — yellow, figure-8 pattern
          let c4x = (math.sin(t * 0.5) * 0.3) as Float32;
          let c4y = (math.cos(t * 0.7) * 0.3) as Float32;
          draw_quad_2d(a, c4x, c4y, 0.08, 0.08, 1.0, 1.0, 0.2);
          // Triangle — cycling rainbow color
          let tr = (math.sin(t) * 0.5 + 0.5) as Float32;
          let tg = (math.sin(t + 2.0) * 0.5 + 0.5) as Float32;
          let tb = (math.sin(t + 4.0) * 0.5 + 0.5) as Float32;
          draw_triangle_2d(a, tr, tg, tb);
          end_frame(a);
        } `elif status == -1 {
          io.println("ERROR: begin_frame failed: " + last_error());
          break;
        }
      }
      destroy_app(a);
      return 0;
    }
  }
}
