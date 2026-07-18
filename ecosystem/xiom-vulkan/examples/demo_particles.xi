// XIOM — Vulkan Particle Fountain Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates the GPU particle system.
module xiom.vulkan.demo_particles

use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Vulkan — Particle Fountain", 800, 600);
  match app {
    Err(e) => {
      io.println(e);
      return 1;
    }
    Ok(a) => {
      let ok = particles_enable(a, 3000);
      if !ok {
        io.println("warning: particles_enable returned false");
      }
      var last = now();
      while !should_close(a) {
        poll(a);
        let t = now();
        let dt = (t - last) as Float32;
        last = t;
        set_clear_color(a, 0.02, 0.02, 0.05);
        let status = begin_frame(a);
        if status == 1 {
          draw_particles(a, dt);
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
