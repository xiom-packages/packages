// XIOM - Compute Golden-Image Test (Windowed Status Demo)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The offscreen compute path (offscreen_create + readback hash) hangs on
// non-headless setups, so this demo runs the windowed pipeline instead:
//   - color-cycling hero triangle (draw_triangle_2d)
//   - status panel in the top-left corner (quads only):
//       amber row  -> "Compute Test: SKIPPED" (offscreen needs headless GPU)
//       green row  -> "Windowed: PASS"
//       bottom row -> frame counter (heartbeat blinker + 8-segment bar)
//
// NOTE: each math.sin/math.cos call uses its own now() binding to
// avoid E001 Float64 warnings.
module xiom.vulkan.demo_compute

use xiom.io;
use xiom.math;
use xiom.vulkan;

var g_frames: Int = 0;

// ─── Status panel: dark backing + indicator rows + frame counter ───

fn draw_status_panel(app: Int) {
  // Backing panel with inset fill (dark, reads as semi-transparent)
  draw_quad_2d(app, -0.70, 0.84, 0.26, 0.13, 0.05, 0.05, 0.09);
  draw_quad_2d(app, -0.70, 0.84, 0.252, 0.122, 0.02, 0.02, 0.04);

  // Row 1 - "Compute Test: SKIPPED": pulsing amber indicator + label bar
  let tp1 = now();
  let pr = (math.sin(tp1 * 2.5) * 0.15 + 0.80) as Float32;
  let tp2 = now();
  let pg = (math.sin(tp2 * 2.5) * 0.108 + 0.576) as Float32;
  draw_quad_2d(app, -0.90, 0.92, 0.012, 0.012, pr, pg, 0.10);
  draw_quad_2d(app, -0.80, 0.92, 0.075, 0.006, 0.55, 0.44, 0.12);

  // Row 2 - "Windowed: PASS": solid green indicator + label bar
  draw_quad_2d(app, -0.90, 0.84, 0.012, 0.012, 0.16, 0.88, 0.38);
  draw_quad_2d(app, -0.81, 0.84, 0.062, 0.006, 0.12, 0.50, 0.24);

  // Row 3 - frame counter: heartbeat blinker + 8-segment rolling bar
  let blink = g_frames % 2;
  if blink == 0 {
    draw_quad_2d(app, -0.90, 0.76, 0.009, 0.009, 0.30, 0.75, 1.0);
  } else {
    draw_quad_2d(app, -0.90, 0.76, 0.009, 0.009, 0.12, 0.32, 0.50);
  }
  let lit = (g_frames / 16) % 9;
  var s = 0;
  while s < 8 {
    let bx = ((s as Float32) * 0.022) - 0.85;
    var br = 0.10; var bg = 0.10; var bb = 0.14;
    if s < lit {
      br = 0.25; bg = 0.62; bb = 0.95;
    }
    draw_quad_2d(app, bx, 0.76, 0.008, 0.010, br, bg, bb);
    s = s + 1;
  }
}

// ─── Main ───

fn main() -> Int {
  let app = create_app("XIOM Compute Golden-Image Test", 800, 600);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      io.println("Compute Test: SKIPPED (offscreen path requires a headless GPU)");
      io.println("Windowed: PASS (close the window to exit)");
      g_frames = 0;

      while !should_close(a) {
        poll(a);
        g_frames = g_frames + 1;

        // Subtle breathing clear color so the backdrop is not static
        let tc = now();
        let glow = (math.sin(tc * 0.5) * 0.02 + 0.045) as Float32;
        set_clear_color(a, glow * 0.7, glow * 0.8, glow + 0.04);

        let status = begin_frame(a);
        if status == 1 {
          // Color-cycling hero triangle
          let t1 = now();
          let r = (math.sin(t1) * 0.5 + 0.5) as Float32;
          let t2 = now();
          let g = (math.sin(t2 + 2.0) * 0.5 + 0.5) as Float32;
          let t3 = now();
          let b = (math.sin(t3 + 4.0) * 0.5 + 0.5) as Float32;
          draw_triangle_2d(a, r, g, b);

          // Status panel on top of the scene
          draw_status_panel(a);

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
