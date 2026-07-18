// XIOM — Vulkan 2D Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates the 2D drawing API in style:
//   - drifting starfield background built from small scattered quads
//   - classic color-cycling hero triangle (draw_triangle_2d)
//   - three counter-rotating triangle rings (0.40 / 0.25 / 0.12)
//     traced with quads, each with its own color and spin direction
//   - pulsing clear-color glow driven by a slow sin wave
//   - simulated FPS meter drawn with small quads in the corner
//
// E001 notes: each math.sin/math.cos call uses its own now() binding,
// and Float32 locals are passed bare as an argument at most once (their
// final use) — multi-use values travel as function parameters instead.
module xiom.vulkan.demo2d

use xiom.io;
use xiom.math;
use xiom.vulkan;

// ─── FPS state ───

var g_frame_count: Int = 0;
var g_last_fps_time: Float64 = 0.0;
var g_fps: Int = 0;

// ─── One star: square quad with a cool blue-white tint ───

fn star(app: Int, sx: Float32, sy: Float32, s: Float32, lum: Float32) {
  draw_quad_2d(app, sx, sy, s, s, lum * 0.85, lum * 0.9, lum + 0.10);
}

// ─── Starfield: scattered small quads with a slow sinusoidal drift ───

fn draw_starfield(app: Int) {
  var i = 0;
  while i < 56 {
    // Deterministic scatter from the star index (no RNG needed)
    let bx = (((i * 73 + 19) % 200) as Float32) * 0.01 - 1.0;
    let by = (((i * 131 + 47) % 200) as Float32) * 0.01 - 1.0;
    let ph = (((i * 37) % 63) as Float64) * 0.1;
    // Slow drift
    let ts1 = now();
    let dx = (math.sin(ts1 * 0.05 + ph) * 0.06) as Float32;
    let ts2 = now();
    let dy = (math.cos(ts2 * 0.04 + ph * 2.0) * 0.06) as Float32;
    // Twinkle
    let ts3 = now();
    let tw = (math.sin(ts3 * 0.9 + ph * 4.0) * 0.18 + 0.42) as Float32;
    let sz = ((i % 3) as Float32) * 0.0016 + 0.0022;
    star(app, bx + dx, by + dy, sz, tw);
    i = i + 1;
  }
}

// ─── Edge renderer: bright vertex marker + dimmer trail of dots ───

fn edge_dots(app: Int, x1: Float32, y1: Float32, x2: Float32, y2: Float32,
             r: Float32, g: Float32, b: Float32, dot: Float32) {
  draw_quad_2d(app, x1, y1, dot * 1.8, dot * 1.8, r, g, b);
  var e = 1;
  while e < 6 {
    let f = (e as Float32) / 6.0;
    let ex = x1 + (x2 - x1) * f;
    let ey = y1 + (y2 - y1) * f;
    draw_quad_2d(app, ex, ey, dot * 1.0, dot * 1.0, r * 0.6, g * 0.6, b * 0.6);
    e = e + 1;
  }
}

// ─── One edge of a rotating triangle ring ───

fn tri_edge(app: Int, radius: Float32, speed: Float64, a0: Float64, a1: Float64,
            r: Float32, g: Float32, b: Float32, dot: Float32) {
  let tn1 = now();
  let x1 = (math.cos(tn1 * speed + a0) as Float32) * radius;
  let tn2 = now();
  let y1 = (math.sin(tn2 * speed + a0) as Float32) * radius;
  let tn3 = now();
  let x2 = (math.cos(tn3 * speed + a1) as Float32) * radius;
  let tn4 = now();
  let y2 = (math.sin(tn4 * speed + a1) as Float32) * radius;
  edge_dots(app, x1, y1, x2, y2, r, g, b, dot);
}

// ─── Full triangle ring: three vertices 120° apart ───

fn tri_ring(app: Int, radius: Float32, speed: Float64, phase: Float64,
            r: Float32, g: Float32, b: Float32, dot: Float32) {
  tri_edge(app, radius, speed, phase, phase + 2.0944, r, g, b, dot);
  tri_edge(app, radius, speed, phase + 2.0944, phase + 4.1888, r, g, b, dot);
  tri_edge(app, radius, speed, phase + 4.1888, phase + 6.2832, r, g, b, dot);
}

// ─── Simulated FPS meter: blinker + segment bars, top-left corner ───

fn draw_fps_meter(app: Int, cx: Float32, cy: Float32) {
  // Backing panel with inset fill
  draw_quad_2d(app, cx, cy, 0.115, 0.030, 0.05, 0.05, 0.09);
  draw_quad_2d(app, cx, cy, 0.111, 0.026, 0.02, 0.02, 0.04);

  // Heartbeat blinker: alternates color every frame
  let blink = g_frame_count % 2;
  if blink == 0 {
    draw_quad_2d(app, cx - 0.095, cy, 0.007, 0.007, 0.20, 0.90, 0.45);
  } else {
    draw_quad_2d(app, cx - 0.095, cy, 0.007, 0.007, 0.10, 0.45, 0.22);
  }

  // Eight FPS segments: lit share of 144 FPS, top two run amber
  var ratio = (g_fps as Float32) / 144.0;
  if ratio > 1.0 { ratio = 1.0; }
  var s = 0;
  while s < 8 {
    let level = (s as Float32) / 8.0;
    var br = 0.10; var bg = 0.10; var bb = 0.14;
    if ratio > level {
      br = 0.18; bg = 0.72; bb = 0.38;
      if s > 5 { br = 0.90; bg = 0.75; bb = 0.20; }
    }
    let bar_x = cx - 0.075 + (s as Float32) * 0.021;
    draw_quad_2d(app, bar_x, cy, 0.008, 0.011, br, bg, bb);
    s = s + 1;
  }
}

// ─── Main ───

fn main() -> Int {
  let app = create_app("XIOM Vulkan 2D", 800, 600);
  match app {
    Err(e) => {
      io.println(e);
      return 1;
    }
    Ok(a) => {
      g_frame_count = 0;
      g_last_fps_time = now();
      g_fps = 0;

      while !should_close(a) {
        poll(a);

        // FPS bookkeeping over a one-second window
        g_frame_count = g_frame_count + 1;
        let tf = now();
        if tf - g_last_fps_time >= 1.0 {
          g_fps = g_frame_count;
          g_frame_count = 0;
          g_last_fps_time = tf;
        }

        // Pulsing glow: slow sin wave modulates clear-color brightness
        let tp = now();
        let glow = (math.sin(tp * 0.6) * 0.03 + 0.055) as Float32;
        set_clear_color(a, glow * 0.6, glow * 0.7, glow + 0.045);

        let status = begin_frame(a);
        if status == 1 {
          // Layer 1 — drifting starfield
          draw_starfield(a);

          // Layer 2 — classic color-cycling hero triangle
          let tr1 = now();
          let r = (math.sin(tr1) * 0.5 + 0.5) as Float32;
          let tr2 = now();
          let g = (math.sin(tr2 + 2.0) * 0.5 + 0.5) as Float32;
          let tr3 = now();
          let b = (math.sin(tr3 + 4.0) * 0.5 + 0.5) as Float32;
          draw_triangle_2d(a, r, g, b);

          // Layer 3 — stacked triangle rings, counter-rotating
          tri_ring(a, 0.40, 0.45, 0.0, 0.25, 0.85, 1.0, 0.011);
          tri_ring(a, 0.25, -0.70, 1.05, 1.0, 0.35, 0.75, 0.009);
          tri_ring(a, 0.12, 1.10, 2.09, 1.0, 0.80, 0.25, 0.007);

          // Layer 4 — simulated FPS meter
          draw_fps_meter(a, -0.86, 0.93);

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
