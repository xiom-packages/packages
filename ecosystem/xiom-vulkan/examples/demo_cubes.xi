// XIOM — Vulkan Cube Field Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates the 3D cube placement API with a grid of spinning cubes.
module xiom.vulkan.demo_cubes

use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Vulkan — Cube Field", 800, 600);
  match app {
    Err(e) => {
      io.println(e);
      return 1;
    }
    Ok(a) => {
      while !should_close(a) {
        poll(a);
        let t = now() as Float32;
        set_clear_color(a, 0.02, 0.02, 0.06);
        let status = begin_frame(a);
        if status == 1 {
          var gx: Int = -1;
          while gx <= 1 {
            var gz: Int = -1;
            while gz <= 1 {
              let px = (gx as Float32) * 1.2;
              let pz = (gz as Float32) * 1.2;
              let offset = (gx * 3 + gz) as Float32 * 0.5;
              draw_cube_3d_at(a, t + offset, px, 0.0, pz, 0.35);
              gz = gz + 1;
            }
            gx = gx + 1;
          }
          end_frame(a);
        } elif status == -1 {
          io.println("ERROR: begin_frame failed: " + last_error());
          break;
        }
      }
      destroy_app(a);
      return 0;
    }
  }
}
