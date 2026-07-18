// XIOM — 3D Viewport Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// A Blender-style 3D viewport: 27 cubes in a 3x3x3 grid observed by an
// orbiting camera. The xvk bridge uses a fixed camera at (2,2,2), so the
// orbit is simulated by rotating every object position through the camera
// basis (cam_x/cam_z below), which yields the same on-screen motion as a
// camera flying around the scene.
module xiom.vulkan.demo_viewport

use xiom.io;
use xiom.math;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Vulkan — 3D Viewport | Orbit Camera", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      while !should_close(a) {
        poll(a);
        let t = now();

        // ---- camera orbit: radius 3.0, one lap roughly every 18 s ----
        let cam_rad = 3.0;
        let cam_x = math.sin(t * 0.35) * cam_rad;
        let cam_z = math.cos(t * 0.35) * cam_rad;
        let cam_bob = math.sin(t * 0.4) * 0.2;

        // dark grey viewport background with a barely visible pulse
        let bg = math.sin(t * 0.25) * 0.005;
        set_clear_color(a, (0.09 + bg) as Float32, 0.09, (0.11 - bg) as Float32);

        let status = begin_frame(a);
        if status == 1 {
          // ---- ground plane: 7x7 dot grid, rotating with the orbit ----
          var gx: Int = -3;
          while gx <= 3 {
            var gz: Int = -3;
            while gz <= 3 {
              let wx = (gx as Float64) * 0.5;
              let wz = (gz as Float64) * 0.5;
              let rx = (wx * cam_z - wz * cam_x) / cam_rad;
              let rz = (wx * cam_x + wz * cam_z) / cam_rad;
              let ry = cam_bob - 1.55;
              draw_cube_3d_at(a, 0.0, rx as Float32, ry as Float32, rz as Float32, 0.025);
              gz = gz + 1;
            }
            gx = gx + 1;
          }

          // ---- 3x3x3 cube grid (27 cubes), spacing 1.1 ----
          var ix: Int = 0;
          while ix < 3 {
            var iy: Int = 0;
            while iy < 3 {
              var iz: Int = 0;
              while iz < 3 {
                let dx = ((ix - 1) as Float64) * 1.1;
                let dy = ((iy - 1) as Float64) * 1.1;
                let dz = ((iz - 1) as Float64) * 1.1;

                // rotate the position through the camera basis: this is
                // what turns the fixed bridge camera into an orbiting one
                let ox = (dx * cam_z - dz * cam_x) / cam_rad;
                let oz = (dx * cam_x + dz * cam_z) / cam_rad;
                let oy = dy + cam_bob;

                // scale hierarchy: centre focus object is largest, then
                // face cubes, edge cubes, and corner cubes shrink outward
                let d2 = dx * dx + dy * dy + dz * dz;
                let center = ix == 1 && iy == 1 && iz == 1;
                var sc: Float32 = 0.13;
                if d2 < 3.0 { sc = 0.18; }
                if d2 < 2.0 { sc = 0.24; }
                if center { sc = 0.34; }

                // rotation: the focus cube spins fast, outer shells slowly
                // counter-rotate with a phase offset per shell
                var rot = d2 * 0.35 - t * 0.45;
                if center { rot = t * 1.3; }

                draw_cube_3d_at(a, rot as Float32, ox as Float32, oy as Float32, oz as Float32, sc);
                iz = iz + 1;
              }
              iy = iy + 1;
            }
            ix = ix + 1;
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
