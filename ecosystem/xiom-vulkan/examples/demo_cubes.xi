// XIOM — Vulkan Cube Field Demo (Awesome Edition)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 5×5 staggered wave grid, central tower, orbiting sparkles, synthwave ground grid.
module xiom.vulkan.demo_cubes

use xiom.io;
use xiom.math;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("XIOM Vulkan — 5×5 Wave Grid + Tower", 1024, 768);
  match app {
    Err(e) => {
      io.println(e);
      return 1;
    }
    Ok(a) => {
      while !should_close(a) {
        poll(a);
        let n0 = now();
        let t = n0 as Float32;

        let nc = now();
        let cr: Float32 = (math.sin(nc * 0.3) * 0.1 + 0.08) as Float32;
        let nc2 = now();
        let cb: Float32 = (math.sin(nc2 * 0.3) * 0.04 + 0.08) as Float32;
        set_clear_color(a, cr, 0.02, cb);

        let status = begin_frame(a);
        if status == 1 {
          // ─── Ground-plane grid (2D synthwave perspective floor) ───
          // Horizontal lines with perspective spacing
          var gy_idx: Int = 0;
          while gy_idx < 24 {
            let gfn = gy_idx as Float32;
            let gy_raw = (gfn * 0.045 * gfn) * 0.08;
            let gy_clamped: Float32 = if gy_raw > 0.92 { 0.92 } else { gy_raw };
            var ga: Float32 = 0.0;
            if gy_clamped > 0.86 { ga = 0.08; }
            elif gy_clamped > 0.78 { ga = 0.12; }
            elif gy_clamped > 0.68 { ga = 0.18; }
            elif gy_clamped > 0.54 { ga = 0.22; }
            elif gy_clamped > 0.38 { ga = 0.28; }
            elif gy_clamped > 0.20 { ga = 0.22; }
            else { ga = 0.12; }
            if ga > 0.001 {
              let ga_dark = ga * 0.7;
              draw_quad_2d(a, 0.0, gy_clamped, 0.98, 0.002,
                           0.0, ga, ga_dark);
            }
            gy_idx = gy_idx + 1;
          }

          // Vertical lines with perspective spread
          var gx_idx: Int = -14;
          while gx_idx <= 14 {
            let gxi = gx_idx as Float32;
            let gx_mag = if gxi < 0.0 { 0.0 - gxi } else { gxi };
            let gx = gxi * 0.025 * gx_mag;
            var gv: Float32 = 0.03;
            if gxi > -2.0 && gxi < 2.0 { gv = 0.08; }
            elif gxi > -6.0 && gxi < 6.0 { gv = 0.06; }
            let gv_g = gv * 0.8;
            draw_quad_2d(a, gx, 0.46, 0.001, 0.46,
                         0.06, gv_g, gv);
            gx_idx = gx_idx + 1;
          }

          // ─── 5×5 wave cube grid ───
          var cx: Int = -2;
          while cx <= 2 {
            var cz: Int = -2;
            while cz <= 2 {
              let cxf = cx as Float32;
              let czf = cz as Float32;
              let px = cxf * 0.8;
              let pz = czf * 0.8;

              let nw = now();
              let cxcz = (cx + cz) as Float64;
              let wave = (math.sin(nw + cxcz * 0.8) as Float32) * 0.45;
              let py = wave;

              let dist2 = (cx * cx + cz * cz) as Float32;
              let speed = 0.3 + dist2 * 0.15;
              let nr_rot = now();
              let rot = (nr_rot as Float32) * speed;

              draw_cube_3d_at(a, rot, px, py, pz, 0.25);
              cz = cz + 1;
            }
            cx = cx + 1;
          }

          // ─── Central tower: pedestal + head crystal at (0,1.5,0) scale 0.5 ───
          let nt1 = now();
          let t1 = nt1 as Float32;
          let taper1 = t1 * 0.6;
          draw_cube_3d_at(a, taper1, 0.0, 0.35, 0.0, 0.22);
          let taper2 = t1 * 0.8;
          draw_cube_3d_at(a, taper2, 0.0, 0.70, 0.0, 0.16);
          let taper3 = t1 * 1.0;
          draw_cube_3d_at(a, taper3, 0.0, 1.05, 0.0, 0.11);

          let nt2 = now();
          let t2_neg = -(nt2 as Float32) * 1.4;
          draw_cube_3d_at(a, t2_neg, 0.0, 1.50, 0.0, 0.5);

          // ─── Sparkle quads orbiting the tower (2D screen-space) ───
          let ns = now();
          let orbit_angle = (ns as Float32) * 1.6;
          var si: Int = 0;
          while si < 6 {
            let sf = si as Float32;

            // Sparkle brightness pulsing (per-sparkle)
            let np = now();
            var sb: Float32 = (math.sin(np + sf as Float64 * 1.3) as Float32) * 0.3 + 0.7;

            // Sparkle color pulse factor: gold=0, cyan=1, white=2
            let nr_sp = now();
            var pulse_raw: Float32 = (math.sin(nr_sp * 3.0) as Float32) * 0.3 + 0.7;
            var pulse: Float32 = pulse_raw * sb;

            // Position on elliptical orbit — recomputed per draw call
            let s_cos1 = sf as Float64 * 1.047 + orbit_angle as Float64;
            var sx1: Float32 = (math.cos(s_cos1) as Float32) * 0.10;
            let s_sin1 = sf as Float64 * 1.047 + orbit_angle as Float64;
            var sy1: Float32 = -0.82 + (math.sin(s_sin1) as Float32) * 0.06;

            if sf < 1.5 {
              let p0 = pulse.clone(); let p1 = pulse.clone(); let p2 = pulse.clone();
              let sxa = sx1.clone(); let sya = sy1.clone();
              draw_quad_2d(a, sxa, sya, 0.03, 0.03,
                           p0 * 0.25, p1 * 0.225, p2 * 0.075);
              let s_cos2 = sf as Float64 * 1.047 + orbit_angle as Float64;
              var sx2: Float32 = (math.cos(s_cos2) as Float32) * 0.10;
              let s_sin2 = sf as Float64 * 1.047 + orbit_angle as Float64;
              var sy2: Float32 = -0.82 + (math.sin(s_sin2) as Float32) * 0.06;
              let p3 = pulse.clone(); let p4 = pulse.clone(); let p5 = pulse;
              draw_quad_2d(a, sx2, sy2, 0.012, 0.012,
                           p3, p4 * 0.9, p5 * 0.3);
            } elif sf < 3.5 {
              let p0 = pulse.clone(); let p1 = pulse.clone(); let p2 = pulse.clone();
              let sxa = sx1.clone(); let sya = sy1.clone();
              draw_quad_2d(a, sxa, sya, 0.03, 0.03,
                           p0 * 0.1, p1 * 0.225, p2 * 0.25);
              let s_cos2 = sf as Float64 * 1.047 + orbit_angle as Float64;
              var sx2: Float32 = (math.cos(s_cos2) as Float32) * 0.10;
              let s_sin2 = sf as Float64 * 1.047 + orbit_angle as Float64;
              var sy2: Float32 = -0.82 + (math.sin(s_sin2) as Float32) * 0.06;
              let p3 = pulse.clone(); let p4 = pulse.clone(); let p5 = pulse;
              draw_quad_2d(a, sx2, sy2, 0.012, 0.012,
                           p3 * 0.4, p4 * 0.9, p5);
            } else {
              let p0 = pulse.clone(); let p1 = pulse.clone(); let p2 = pulse.clone();
              let sxa = sx1.clone(); let sya = sy1.clone();
              draw_quad_2d(a, sxa, sya, 0.03, 0.03,
                           p0 * 0.25, p1 * 0.25, p2 * 0.25);
              let s_cos2 = sf as Float64 * 1.047 + orbit_angle as Float64;
              var sx2: Float32 = (math.cos(s_cos2) as Float32) * 0.10;
              let s_sin2 = sf as Float64 * 1.047 + orbit_angle as Float64;
              var sy2: Float32 = -0.82 + (math.sin(s_sin2) as Float32) * 0.06;
              let p3 = pulse.clone(); let p4 = pulse.clone(); let p5 = pulse;
              draw_quad_2d(a, sx2, sy2, 0.012, 0.012,
                           p3, p4, p5);
            }
            si = si + 1;
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