// XIOM — Vulkan 3D Demo (Spinning Cube)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates the 3D spinning cube API.
module xiom.vulkan.demo3d

use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Vulkan 3D — Spinning Cube", 800, 600);
  match app {
    Err(e) => {
      io.println(e);
      return 1;
    }
    Ok(a) => {
      while !should_close(a) {
        poll(a);
        let angle = now() as Float32;
        set_clear_color(a, 0.05, 0.05, 0.1);
        let status = begin_frame(a);
        if status == 1 {
          draw_cube_3d(a, angle);
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
