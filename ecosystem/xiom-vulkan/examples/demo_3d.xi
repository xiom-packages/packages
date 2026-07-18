// XIOM — Vulkan 3D Demo (Orbital Cube Showcase)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// A polished 3D scene: a fast-spinning central cube, three cubes
// orbiting at 1.5 / 2.5 / 3.5 units with unique speeds and phases,
// a 30-star drifting background, per-cube color zones, and a clear
// color that pulses on a slow sin wave.
module xiom.vulkan.demo3d

use xiom.io;
use xiom.math;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Vulkan 3D — Orbital Cubes", 1024, 768);
  match app {
    Err(e) => {
      io.println(e);
      return 1;
    }
    Ok(a) => {
      while !should_close(a) {
        poll(a);

        // Clear color pulses on a slow sin wave (~15s period)
        let nc = now();
        let pulse = math.sin(nc * 0.4) * 0.5 + 0.5;
        let cr = (0.02 + pulse * 0.04) as Float32;
        let cg = (0.02 + pulse * 0.03) as Float32;
        let cb = (0.07 + pulse * 0.07) as Float32;
        set_clear_color(a, cr, cg, cb);

        let status = begin_frame(a);
        if status == 1 {
          // Color zones — one background region per cube (drawn first,
          // quads have no depth write so the 3D cubes render on top)
          draw_quad_2d(a, 0.0, 0.0, 0.42, 0.42, 0.09, 0.06, 0.03);   // center: amber
          draw_quad_2d(a, -0.71, 0.0, 0.29, 1.0, 0.02, 0.07, 0.09);  // left band: cyan
          draw_quad_2d(a, 0.71, 0.0, 0.29, 1.0, 0.08, 0.03, 0.09);   // right band: magenta
          draw_quad_2d(a, 0.0, 0.71, 0.42, 0.29, 0.03, 0.08, 0.04);  // lower band: green

          // Starfield — 30 stars scattered by index hash, slowly drifting
          var i: Int = 0;
          while i < 30 {
            let fi = i as Float64;
            let bx = math.sin(fi * 12.9898) * 0.95;
            let by = math.cos(fi * 78.233) * 0.95;
            let ndx = now();
            let dx = math.sin(ndx * 0.07 + fi * 1.9) * 0.05;
            let ndy = now();
            let dy = math.cos(ndy * 0.09 + fi * 2.3) * 0.04;
            let sx = (bx + dx) as Float32;
            let sy = (by + dy) as Float32;
            let tw = math.sin(fi * 45.164) * 0.5 + 0.5;
            let shw = (0.002 + tw * 0.004) as Float32;
            let shh = (0.002 + tw * 0.004) as Float32;
            let sr = (0.45 + tw * 0.4) as Float32;
            let sg = (0.45 + tw * 0.4) as Float32;
            let sb = (0.55 + tw * 0.4) as Float32;
            draw_quad_2d(a, sx, sy, shw, shh, sr, sg, sb);
            i = i + 1;
          }

          // Central cube — stationary, spins faster than the orbiters
          let nspin = now();
          let spin = (nspin * 1.8) as Float32;
          draw_cube_3d(a, spin);

          // Orbiter 1 — inner ring, 1.5 units, fastest orbit, phase 0
          let n1x = now();
          let px1 = (math.sin(n1x * 0.9) * 1.5) as Float32;
          let n1z = now();
          let pz1 = (math.cos(n1z * 0.9) * 1.5) as Float32;
          let n1r = now();
          let rot1 = (n1r * 1.4) as Float32;
          draw_cube_3d_at(a, rot1, px1, 0.0, pz1, 0.30);

          // Orbiter 2 — middle ring, 2.5 units, phase +120 degrees
          let n2x = now();
          let px2 = (math.sin(n2x * 0.55 + 2.094) * 2.5) as Float32;
          let n2z = now();
          let pz2 = (math.cos(n2z * 0.55 + 2.094) * 2.5) as Float32;
          let n2r = now();
          let rot2 = (n2r * 1.0 + 2.094) as Float32;
          draw_cube_3d_at(a, rot2, px2, 0.35, pz2, 0.24);

          // Orbiter 3 — outer ring, 3.5 units, phase +240 degrees
          let n3x = now();
          let px3 = (math.sin(n3x * 0.35 + 4.189) * 3.5) as Float32;
          let n3z = now();
          let pz3 = (math.cos(n3z * 0.35 + 4.189) * 3.5) as Float32;
          let n3r = now();
          let rot3 = (n3r * 0.7 + 4.189) as Float32;
          draw_cube_3d_at(a, rot3, px3, -0.35, pz3, 0.20);

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
