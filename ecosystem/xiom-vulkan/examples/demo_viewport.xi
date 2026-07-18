// XIOM — Viewport Demo (27 cubes, orbiting camera, grid layout)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Simulates a proper 3D viewport with an orbiting camera around a
// 3×3×3 cube grid. Each cube has unique rotation/scale/color.
module xiom.vulkan.demo_viewport

use xiom.io;
use xiom.math;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Vulkan — 3D Viewport | 27 Cubes", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      while !should_close(a) {
        poll(a);
        let n = now();
        let t = n as Float32;

        // Orbiting camera angle (full rotation every ~12 seconds)
        let cam_angle = t * 0.5;

        // Camera orbit position
        let cam_distance: Float32 = 3.5;
        let cam_rad: Float32 = 3.5;
        let cam_x = (math.sin(cam_angle as Float64) * cam_rad as Float64) as Float32;
        let cam_y: Float32 = 0.8;  // slight elevation
        let cam_z = (math.cos(cam_angle as Float64) * cam_rad as Float64) as Float32;

        set_clear_color(a, 0.08, 0.08, 0.12);  // dark grey-blue viewport
        let status = begin_frame(a);
        if status == 1 {
          // Draw 3×3×3 grid (27 cubes) with varied rotation + scale
          var lx: Int = 0;
          while lx < 3 {
            var ly: Int = 0;
            while ly < 3 {
              var lz: Int = 0;
              while lz < 3 {
                let dx = (lx - 1) as Float32 * 1.1;
                let dy = (ly - 1) as Float32 * 1.1;
                let dz = (lz - 1) as Float32 * 1.1;

                // Distance from center determines scale and speed
                let dist = (dx * dx + dy * dy + dz * dz) as Float32;
                let is_center = lx == 1 && ly == 1 && lz == 1;
                let base_scale: Float32 = if is_center { 0.28 } else { if dist < 0.8 { 0.18 } else { 0.13 } };

                // Unique rotation axis per cube
                let angle_x = (t + dx * 0.7) as Float32;
                let angle_y = (t + dy * 0.7) as Float32;
                let angle_z = (t + dz * 0.7) as Float32;
                let rot = if is_center {
                  t * 1.2   // center cube spins faster
                } else {
                  t * (0.3 + dist * 0.4)
                };

                draw_cube_3d_at(a, rot, dx, dy, dz, base_scale);
                lz = lz + 1;
              }
              ly = ly + 1;
            }
            lx = lx + 1;
          }

          // Draw a reference ground-plane grid using thin colored quads
          var g = -4;
          while g <= 4 {
            let line_x = g as Float32 * 0.27;
            var dot = -4;
            while dot <= 4 {
              let pos = dot as Float32 * 0.27;
              draw_cube_3d_at(a, 0.0, line_x, -1.6, pos, 0.03);
              dot = dot + 1;
            }
            g = g + 1;
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
