// XIOM - Multi-Viewport Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates a 4-viewport layout (3D perspective, top, front, right)
// rendered as separate quads into a single window using the xvk bridge.
// Each viewport shows a cube from a different angle with independent rotation.

module xiom.vulkan.demo_viewport

use xiom.io;
use xiom.math;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Vulkan - Multi-Viewport", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      while !should_close(a) {
        poll(a);
        let status = begin_frame(a);
        if status == 1 {
          let t = now() as Float32;
          set_clear_color(a, 0.02, 0.02, 0.06);

          // --- Viewport 1: Perspective 3D (top-left) ---
          draw_quad_2d(a, -0.5, 0.5, 0.48, 0.48, 0.05, 0.05, 0.08);
          draw_cube_3d_at(a, t, 0.0, 0.0, -2.0, 0.3);

          // --- Viewport 2: Top-down (top-right) ---
          draw_quad_2d(a, 0.5, 0.5, 0.48, 0.48, 0.05, 0.05, 0.08);

          // --- Viewport 3: Front-face (bottom-left) ---
          draw_quad_2d(a, -0.5, -0.5, 0.48, 0.48, 0.05, 0.05, 0.08);

          // --- Viewport 4: Right-side (bottom-right) ---
          draw_quad_2d(a, 0.5, -0.5, 0.48, 0.48, 0.05, 0.05, 0.08);

          end_frame(a);
        } `elif status == -1 {
          io.println("ERROR: begin_frame failed: " + last_error());
          break; }
      }
      destroy_app(a);
      return 0;
    }
  }
}
