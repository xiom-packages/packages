// XIOM - Interactive UI Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Full interactive GUI: toolbar, sidebar, viewport, status bar.
// Nested quads simulate rounded-rect buttons, panel borders,
// and pixel-art labels. Elements animate on a timer.

module xiom.vulkan.demo_ui

use xiom.io;
use xiom.math;
use xiom.vulkan;

// ─── Shared animation state ───

var g_frame_count: Int = 0;
var g_last_fps_time: Float64 = 0.0;
var g_fps: Int = 0;

// ─── Panel helper: outer border + inset fill ───

fn panel(app: Int, cx: Float32, cy: Float32, hw: Float32, hh: Float32,
         br: Float32, bg: Float32, bb: Float32,
         fr: Float32, fg: Float32, fb: Float32) {
  draw_quad_2d(app, cx, cy, hw, hh, br, bg, bb);
  draw_quad_2d(app, cx, cy, hw - 0.004, hh - 0.004, fr, fg, fb);
}

// ─── Button: border + two-tone face + label bar ───

fn button(app: Int, cx: Float32, cy: Float32, hw: Float32, hh: Float32,
           state: Int, accent_r: Float32, accent_g: Float32, accent_b: Float32) {
  var top_r = 0.18;  var top_g = 0.22;  var top_b = 0.27;
  var bot_r = 0.12;  var bot_g = 0.15;  var bot_b = 0.20;
  var bor_r = 0.05;  var bor_g = 0.05;  var bor_b = 0.06;

  if state == 0 {
    top_r = 0.18; top_g = 0.22; top_b = 0.27;
    bot_r = 0.12; bot_g = 0.15; bot_b = 0.20;
    bor_r = 0.05; bor_g = 0.05; bor_b = 0.06;
  } elif state == 1 {
    top_r = 0.24; top_g = 0.28; top_b = 0.34;
    bot_r = 0.16; bot_g = 0.20; bot_b = 0.25;
    bor_r = 0.07; bor_g = 0.07; bor_b = 0.09;
  } elif state == 2 {
    top_r = 0.10; top_g = 0.13; top_b = 0.17;
    bot_r = 0.16; bot_g = 0.20; bot_b = 0.25;
    bor_r = 0.04; bor_g = 0.04; bor_b = 0.05;
  }

  // Border
  draw_quad_2d(app, cx, cy, hw + 0.002, hh + 0.002, bor_r, bor_g, bor_b);
  // Face top half
  draw_quad_2d(app, cx, cy + hh * 0.25, hw - 0.002, hh * 0.50 - 0.002, top_r, top_g, top_b);
  // Face bottom half
  draw_quad_2d(app, cx, cy - hh * 0.25, hw - 0.002, hh * 0.50 - 0.002, bot_r, bot_g, bot_b);
  // Accent colored strip at bottom
  draw_quad_2d(app, cx, cy - hh + 0.005, hw - 0.006, 0.003, accent_r, accent_g, accent_b);
}

// ─── Slider: track + moving thumb ───

fn slider(app: Int, cx: Float32, cy: Float32, hw: Float32, hh: Float32,
          value: Float32, thumb_r: Float32, thumb_g: Float32, thumb_b: Float32) {
  // Track groove
  draw_quad_2d(app, cx, cy, hw, hh, 0.07, 0.07, 0.10);
  // Track fill
  draw_quad_2d(app, cx, cy, hw * 0.96, hh * 0.50, 0.04, 0.04, 0.06);
  // Active track (from left to thumb)
  let fill_hw = value * hw;
  if fill_hw > 0.002 {
    draw_quad_2d(app, cx - hw + fill_hw, cy, fill_hw, hh * 0.50, thumb_r * 0.6, thumb_g * 0.6, thumb_b * 0.6);
  }
  // Thumb
  let tx = cx - hw + value * hw * 2.0;
  draw_quad_2d(app, tx, cy, hh * 2.2, hh * 2.8, thumb_r, thumb_g, thumb_b);
  draw_quad_2d(app, tx, cy + hh * 1.2, hh * 1.2, hh * 0.9, thumb_r + 0.12, thumb_g + 0.12, thumb_b + 0.12);
}

// ─── Icon helpers (small quads arranged as symbols) ───

fn icon_folder(app: Int, cx: Float32, cy: Float32, s: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(app, cx, cy - s * 0.01, s * 0.30, s * 0.22, r, g, b);
  draw_quad_2d(app, cx - s * 0.16, cy + s * 0.26, s * 0.12, s * 0.06, r + 0.06, g + 0.06, b + 0.06);
}

fn icon_gear(app: Int, cx: Float32, cy: Float32, s: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(app, cx, cy, s * 0.16, s * 0.16, r, g, b);
  draw_quad_2d(app, cx + s * 0.20, cy, s * 0.06, s * 0.04, r - 0.04, g - 0.04, b - 0.04);
  draw_quad_2d(app, cx - s * 0.20, cy, s * 0.06, s * 0.04, r - 0.04, g - 0.04, b - 0.04);
  draw_quad_2d(app, cx, cy + s * 0.20, s * 0.04, s * 0.06, r - 0.04, g - 0.04, b - 0.04);
  draw_quad_2d(app, cx, cy - s * 0.20, s * 0.04, s * 0.06, r - 0.04, g - 0.04, b - 0.04);
}

fn icon_play(app: Int, cx: Float32, cy: Float32, s: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(app, cx + s * 0.07, cy, s * 0.04, s * 0.20, r, g, b);
  draw_quad_2d(app, cx - s * 0.06, cy + s * 0.10, s * 0.08, s * 0.08, r, g, b);
  draw_quad_2d(app, cx - s * 0.06, cy - s * 0.10, s * 0.08, s * 0.08, r, g, b);
}

fn icon_star(app: Int, cx: Float32, cy: Float32, s: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(app, cx, cy, s * 0.06, s * 0.06, r, g, b);
  draw_quad_2d(app, cx, cy + s * 0.18, s * 0.035, s * 0.10, r, g, b);
  draw_quad_2d(app, cx, cy - s * 0.18, s * 0.035, s * 0.10, r, g, b);
  draw_quad_2d(app, cx + s * 0.18, cy, s * 0.10, s * 0.035, r, g, b);
  draw_quad_2d(app, cx - s * 0.18, cy, s * 0.10, s * 0.035, r, g, b);
  draw_quad_2d(app, cx + s * 0.10, cy + s * 0.10, s * 0.05, s * 0.05, r - 0.04, g - 0.04, b - 0.04);
  draw_quad_2d(app, cx - s * 0.10, cy + s * 0.10, s * 0.05, s * 0.05, r - 0.04, g - 0.04, b - 0.04);
  draw_quad_2d(app, cx + s * 0.10, cy - s * 0.10, s * 0.05, s * 0.05, r - 0.04, g - 0.04, b - 0.04);
  draw_quad_2d(app, cx - s * 0.10, cy - s * 0.10, s * 0.05, s * 0.05, r - 0.04, g - 0.04, b - 0.04);
}

fn icon_cross(app: Int, cx: Float32, cy: Float32, s: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(app, cx, cy, s * 0.23, s * 0.06, r, g, b);
  draw_quad_2d(app, cx, cy, s * 0.06, s * 0.23, r, g, b);
}

fn icon_mail(app: Int, cx: Float32, cy: Float32, s: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(app, cx, cy - s * 0.02, s * 0.28, s * 0.18, r, g, b);
  draw_quad_2d(app, cx, cy + s * 0.14, s * 0.28, s * 0.04, r + 0.05, g + 0.05, b + 0.05);
}

fn icon_lock(app: Int, cx: Float32, cy: Float32, s: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(app, cx, cy - s * 0.04, s * 0.18, s * 0.16, r, g, b);
  draw_quad_2d(app, cx, cy + s * 0.12, s * 0.10, s * 0.08, r + 0.04, g + 0.04, b + 0.04);
  draw_quad_2d(app, cx, cy + s * 0.23, s * 0.04, s * 0.04, r + 0.08, g + 0.08, b + 0.08);
}

// ─── Label bar: simple horizontal strip as text placeholder ───

fn label_bar(app: Int, cx: Float32, cy: Float32, hw: Float32, hh: Float32,
             r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(app, cx, cy, hw, hh, r, g, b);
}

// ─── Top Toolbar ───

fn draw_toolbar(app: Int, t: Float32) {
  let cx = 0.0;
  let cy = 0.953;
  let hw = 1.0;
  let hh = 0.047;

  // Background
  draw_quad_2d(app, cx, cy, hw, hh, 0.10, 0.10, 0.13);
  // Top highlight strip
  draw_quad_2d(app, cx, cy + hh - 0.002, hw, 0.002, 0.20, 0.20, 0.24);
  // Bottom separator
  draw_quad_2d(app, cx, cy - hh + 0.003, hw, 0.003, 0.04, 0.04, 0.06);

  var bx = cx - hw + 0.07;
  var by = cy;
  var bw = 0.06;
  var bh = hh * 0.62;
  var gap = 0.075;

  // File (folder icon)
  let s0 = ((t * 0.55) as Int) % 3;
  button(app, bx, by, bw, bh, s0, 0.18, 0.68, 0.35);
  icon_folder(app, bx, by + bh * 0.22, bh * 0.70, 0.78, 0.78, 0.82);

  // Settings (gear icon)
  let s1 = (((t + 0.5) * 0.55) as Int) % 3;
  button(app, bx + gap, by, bw, bh, s1, 0.18, 0.55, 0.82);
  icon_gear(app, bx + gap, by + bh * 0.22, bh * 0.70, 0.78, 0.78, 0.82);

  // Run (play icon)
  let s2 = (((t + 1.0) * 0.55) as Int) % 3;
  button(app, bx + gap * 2.0, by, bw, bh, s2, 0.82, 0.55, 0.18);
  icon_play(app, bx + gap * 2.0, by + bh * 0.22, bh * 0.70, 0.78, 0.78, 0.82);

  // Favorite (star icon)
  let s3 = (((t + 1.6) * 0.55) as Int) % 3;
  button(app, bx + gap * 3.0, by, bw, bh, s3, 0.82, 0.28, 0.28);
  icon_star(app, bx + gap * 3.0, by + bh * 0.22, bh * 0.70, 0.94, 0.88, 0.32);

  // Title area
  let tx = cx + hw * 0.32;
  label_bar(app, tx - 0.02, by, 0.07, 0.013, 0.62, 0.62, 0.67);
  label_bar(app, tx + 0.08, by, 0.06, 0.013, 0.52, 0.52, 0.57);
}

// ─── Left Sidebar ───

fn draw_sidebar(app: Int, t: Float32) {
  let cx = -0.844;
  let cy = -0.008;
  let hw = 0.156;
  let hh = 0.89;

  // Panel with border
  panel(app, cx, cy, hw, hh, 0.05, 0.05, 0.08, 0.09, 0.09, 0.12);

  // Right edge highlight
  draw_quad_2d(app, cx + hw - 0.002, cy, 0.002, hh - 0.01, 0.06, 0.06, 0.09);

  // Sidebar header
  let hy = cy + hh - 0.04;
  draw_quad_2d(app, cx, hy, hw - 0.015, 0.025, 0.11, 0.11, 0.15);
  label_bar(app, cx - 0.02, hy, 0.06, 0.011, 0.52, 0.52, 0.57);

  // Navigation buttons
  var bw = hw * 0.78;
  var bh = 0.028;
  var start_y = hy - 0.048;
  var step = 0.050;

  // Project
  let n0 = (((t + 0.2) * 0.52) as Int) % 3;
  button(app, cx, start_y, bw, bh, n0, 0.18, 0.68, 0.35);
  icon_folder(app, cx - bw * 0.50, start_y + bh * 0.22, bh * 0.75, 0.72, 0.72, 0.77);
  label_bar(app, cx + bw * 0.08, start_y, bw * 0.30, bh * 0.14, 0.60, 0.60, 0.65);

  // Settings
  let n1 = (((t + 0.7) * 0.52) as Int) % 3;
  button(app, cx, start_y - step, bw, bh, n1, 0.18, 0.55, 0.82);
  icon_gear(app, cx - bw * 0.50, start_y - step + bh * 0.22, bh * 0.75, 0.72, 0.72, 0.77);
  label_bar(app, cx + bw * 0.08, start_y - step, bw * 0.35, bh * 0.14, 0.60, 0.60, 0.65);

  // Run
  let n2 = (((t + 1.2) * 0.52) as Int) % 3;
  button(app, cx, start_y - step * 2.0, bw, bh, n2, 0.82, 0.55, 0.18);
  icon_play(app, cx - bw * 0.50, start_y - step * 2.0 + bh * 0.22, bh * 0.75, 0.72, 0.72, 0.77);
  label_bar(app, cx + bw * 0.08, start_y - step * 2.0, bw * 0.17, bh * 0.14, 0.60, 0.60, 0.65);

  // Favorites
  let n3 = (((t + 1.7) * 0.52) as Int) % 3;
  button(app, cx, start_y - step * 3.0, bw, bh, n3, 0.82, 0.28, 0.28);
  icon_star(app, cx - bw * 0.50, start_y - step * 3.0 + bh * 0.22, bh * 0.75, 0.90, 0.85, 0.30);
  label_bar(app, cx + bw * 0.08, start_y - step * 3.0, bw * 0.33, bh * 0.14, 0.60, 0.60, 0.65);

  // Messages
  let n4 = (((t + 2.2) * 0.52) as Int) % 3;
  button(app, cx, start_y - step * 4.0, bw, bh, n4, 0.60, 0.45, 0.18);
  icon_mail(app, cx - bw * 0.50, start_y - step * 4.0 + bh * 0.22, bh * 0.75, 0.72, 0.72, 0.77);
  label_bar(app, cx + bw * 0.08, start_y - step * 4.0, bw * 0.32, bh * 0.14, 0.60, 0.60, 0.65);

  // Lock (disabled style)
  let n5 = (((t + 2.7) * 0.52) as Int) % 3;
  button(app, cx, start_y - step * 5.0, bw, bh, 0, 0.35, 0.35, 0.40);
  icon_lock(app, cx - bw * 0.50, start_y - step * 5.0 + bh * 0.22, bh * 0.75, 0.50, 0.50, 0.55);
  label_bar(app, cx + bw * 0.08, start_y - step * 5.0, bw * 0.22, bh * 0.14, 0.45, 0.45, 0.50);

  // Exit
  let n6 = (((t + 3.2) * 0.52) as Int) % 3;
  button(app, cx, start_y - step * 6.0, bw, bh, n6, 0.60, 0.20, 0.20);
  icon_cross(app, cx - bw * 0.50, start_y - step * 6.0 + bh * 0.22, bh * 0.75, 0.72, 0.72, 0.77);
  label_bar(app, cx + bw * 0.08, start_y - step * 6.0, bw * 0.18, bh * 0.14, 0.60, 0.60, 0.65);
}

// ─── Main Viewport Panel ───

fn draw_viewport(app: Int, t: Float32) {
  let cx = 0.16;
  let cy = -0.008;
  let hw = 0.84;
  let hh = 0.89;

  // Border + background
  panel(app, cx, cy, hw, hh, 0.04, 0.04, 0.07, 0.07, 0.07, 0.10);

  // Tab bar
  let tab_y = cy + hh - 0.045;
  draw_quad_2d(app, cx, tab_y, hw - 0.01, 0.033, 0.10, 0.10, 0.14);
  draw_quad_2d(app, cx, tab_y - 0.017, hw - 0.01, 0.001, 0.07, 0.07, 0.10);

  // Active tab
  let tab_w = 0.055;
  let tab_h = 0.026;
  let tab1_x = cx - hw + 0.075;
  draw_quad_2d(app, tab1_x, tab_y + 0.003, tab_w, tab_h, 0.15, 0.15, 0.19);
  draw_quad_2d(app, tab1_x, tab_y + 0.003, tab_w - 0.002, tab_h - 0.002, 0.08, 0.08, 0.11);
  label_bar(app, tab1_x - tab_w * 0.2, tab_y + 0.006, tab_w * 0.18, tab_h * 0.16, 0.18, 0.62, 0.85);
  label_bar(app, tab1_x + tab_w * 0.05, tab_y + 0.006, tab_w * 0.35, tab_h * 0.16, 0.58, 0.58, 0.63);

  // Inactive tabs
  let tab2_x = tab1_x + tab_w + 0.06;
  draw_quad_2d(app, tab2_x, tab_y + 0.001, tab_w, tab_h, 0.10, 0.10, 0.14);
  label_bar(app, tab2_x - tab_w * 0.2, tab_y + 0.004, tab_w * 0.18, tab_h * 0.16, 0.35, 0.35, 0.42);
  label_bar(app, tab2_x + tab_w * 0.05, tab_y + 0.004, tab_w * 0.30, tab_h * 0.16, 0.52, 0.52, 0.57);

  let tab3_x = tab2_x + tab_w + 0.06;
  draw_quad_2d(app, tab3_x, tab_y + 0.001, tab_w, tab_h, 0.10, 0.10, 0.14);
  label_bar(app, tab3_x - tab_w * 0.2, tab_y + 0.004, tab_w * 0.18, tab_h * 0.16, 0.35, 0.35, 0.42);
  label_bar(app, tab3_x + tab_w * 0.05, tab_y + 0.004, tab_w * 0.28, tab_h * 0.16, 0.52, 0.52, 0.57);

  // Content area: grid of placeholder items
  var gi = 0;
  var gx_start = cx - hw + 0.07;
  var gy_start = cy + hh * 0.35;
  while gi < 24 {
    let gx = gx_start + ((gi % 6) as Float32) * 0.10;
    let gy = gy_start - ((gi / 6) as Float32) * 0.10;
    // File/folder item
    draw_quad_2d(app, gx, gy, 0.042, 0.036, 0.11, 0.11, 0.15);
    let g_hue = ((gi as Float32) * 0.27 + t * 0.1) as Float32;
    let ig_r = (math.sin(g_hue as Float64) * 0.25 + 0.35) as Float32;
    let ig_g = (math.sin((g_hue + 2.1) as Float64) * 0.25 + 0.35) as Float32;
    let ig_b = (math.sin((g_hue + 4.2) as Float64) * 0.25 + 0.35) as Float32;
    icon_folder(app, gx, gy + 0.012, 0.038, ig_r, ig_g, ig_b);
    label_bar(app, gx, gy - 0.018, 0.025, 0.005, 0.42, 0.42, 0.48);
    gi = gi + 1;
  }

  // Sliders section
  let sly = cy - hh * 0.28;
  let sl_label_x = cx - hw + 0.07;

  let sv1 = (math.sin(t as Float64) * 0.5 + 0.5) as Float32;
  label_bar(app, sl_label_x, sly + 0.17, 0.025, 0.007, 0.50, 0.50, 0.55);
  slider(app, cx + 0.04, sly + 0.17, 0.22, 0.006, sv1, 0.18, 0.62, 0.85);

  let sv2 = (math.sin((t + 1.5) as Float64) * 0.5 + 0.5) as Float32;
  label_bar(app, sl_label_x, sly + 0.10, 0.025, 0.007, 0.50, 0.50, 0.55);
  slider(app, cx + 0.04, sly + 0.10, 0.22, 0.006, sv2, 0.82, 0.55, 0.18);

  let sv3 = (math.sin((t + 3.0) as Float64) * 0.5 + 0.5) as Float32;
  label_bar(app, sl_label_x, sly + 0.03, 0.025, 0.007, 0.50, 0.50, 0.55);
  slider(app, cx + 0.04, sly + 0.03, 0.22, 0.006, sv3, 0.18, 0.68, 0.35);

  // Color picker
  let cp_x = cx + hw * 0.32;
  let cp_y = cy - hh * 0.08;
  let cp_size = 0.06;

  panel(app, cp_x, cp_y, cp_size * 1.7, cp_size * 3.4, 0.08, 0.08, 0.11, 0.10, 0.10, 0.14);

  let cr = (math.sin((t * 0.7) as Float64) * 0.5 + 0.5) as Float32;
  let cg = (math.sin((t * 0.7 + 2.1) as Float64) * 0.5 + 0.5) as Float32;
  let cb = (math.sin((t * 0.7 + 4.2) as Float64) * 0.5 + 0.5) as Float32;

  // Color swatch
  draw_quad_2d(app, cp_x, cp_y + cp_size * 2.5, cp_size + 0.003, cp_size + 0.003, 0.18, 0.18, 0.20);
  draw_quad_2d(app, cp_x, cp_y + cp_size * 2.5, cp_size, cp_size, cr, cg, cb);

  // R track
  draw_quad_2d(app, cp_x, cp_y + cp_size * 1.3, cp_size, 0.006, 0.08, 0.08, 0.12);
  draw_quad_2d(app, cp_x - cp_size + cr * cp_size, cp_y + cp_size * 1.3, 0.006, 0.012, cr, 0.04, 0.04);
  label_bar(app, cp_x - cp_size - 0.02, cp_y + cp_size * 1.3, 0.01, 0.005, 0.60, 0.15, 0.15);

  // G track
  draw_quad_2d(app, cp_x, cp_y + cp_size * 0.9, cp_size, 0.006, 0.08, 0.08, 0.12);
  draw_quad_2d(app, cp_x - cp_size + cg * cp_size, cp_y + cp_size * 0.9, 0.006, 0.012, 0.04, cg, 0.04);
  label_bar(app, cp_x - cp_size - 0.02, cp_y + cp_size * 0.9, 0.01, 0.005, 0.15, 0.60, 0.15);

  // B track
  draw_quad_2d(app, cp_x, cp_y + cp_size * 0.5, cp_size, 0.006, 0.08, 0.08, 0.12);
  draw_quad_2d(app, cp_x - cp_size + cb * cp_size, cp_y + cp_size * 0.5, 0.006, 0.012, 0.04, 0.04, cb);
  label_bar(app, cp_x - cp_size - 0.02, cp_y + cp_size * 0.5, 0.01, 0.005, 0.15, 0.15, 0.60);

  // HEX label
  label_bar(app, cp_x, cp_y + cp_size * 0.06, cp_size * 0.7, 0.005, 0.42, 0.42, 0.47);
  label_bar(app, cp_x, cp_y - cp_size * 0.06, cp_size * 0.6, 0.005, 0.38, 0.38, 0.43);

  // Action buttons at bottom
  let ab_y = cy - hh * 0.38;
  let ab_x = cx + hw * 0.26;
  let ab_w = 0.055;
  let ab_h = 0.024;

  // OK
  let a0 = (((t + 0.8) * 0.65) as Int) % 3;
  button(app, ab_x, ab_y, ab_w, ab_h, a0, 0.18, 0.68, 0.35);
  label_bar(app, ab_x + 0.003, ab_y, ab_w * 0.12, ab_h * 0.16, 0.75, 0.75, 0.78);

  // Cancel
  let a1 = (((t + 1.3) * 0.65) as Int) % 3;
  button(app, ab_x + ab_w + 0.07, ab_y, ab_w, ab_h, a1, 0.60, 0.25, 0.25);
  label_bar(app, ab_x + ab_w + 0.07 + 0.003, ab_y, ab_w * 0.24, ab_h * 0.16, 0.75, 0.75, 0.78);

  // Apply
  let a2 = (((t + 1.8) * 0.65) as Int) % 3;
  button(app, ab_x + (ab_w + 0.07) * 2.0, ab_y, ab_w, ab_h, a2, 0.18, 0.55, 0.82);
  label_bar(app, ab_x + (ab_w + 0.07) * 2.0 + 0.003, ab_y, ab_w * 0.22, ab_h * 0.16, 0.75, 0.75, 0.78);
}

// ─── Bottom Status Bar ───

fn draw_statusbar(app: Int, t: Float32) {
  let cx = 0.0;
  let cy = -0.969;
  let hw = 1.0;
  let hh = 0.031;

  draw_quad_2d(app, cx, cy, hw, hh, 0.10, 0.10, 0.13);
  draw_quad_2d(app, cx, cy + hh - 0.002, hw, 0.002, 0.20, 0.20, 0.24);

  // Status dot (pulsing green)
  let dot_pulse = (math.sin((t * 1.2) as Float64) * 0.15 + 0.55) as Float32;
  draw_quad_2d(app, cx - hw + 0.035, cy, 0.008, 0.008, 0.15, dot_pulse + 0.35, 0.15);
  draw_quad_2d(app, cx - hw + 0.035, cy, 0.004, 0.004, 0.25, dot_pulse + 0.50, 0.25);

  // Status text
  label_bar(app, cx - hw + 0.085, cy, 0.035, 0.008, 0.52, 0.52, 0.57);
  label_bar(app, cx - hw + 0.145, cy, 0.03, 0.008, 0.45, 0.45, 0.50);
  label_bar(app, cx - hw + 0.195, cy, 0.028, 0.008, 0.45, 0.45, 0.50);

  // FPS area
  let fx = cx + hw * 0.33;
  label_bar(app, fx - 0.04, cy, 0.025, 0.008, 0.45, 0.45, 0.50);
  label_bar(app, fx, cy, 0.025, 0.008, 0.45, 0.45, 0.50);

  // FPS value: bar graph style — bar height proportional to FPS / 120
  let fps_ratio = (g_fps as Float32) / 120.0;
  if fps_ratio > 1.0 { fps_ratio = 1.0; }
  var bar_i = 0;
  var bar_x = fx + 0.035;
  while bar_i < 6 {
    let bv = ((bar_i as Float32) / 6.0) as Float32;
    let bar_on = 0.0;
    if fps_ratio > bv { bar_on = 1.0; }
    let br = 0.18; let bg = 0.68; let bb = 0.35;
    if bar_on < 0.5 {
      br = 0.12; bg = 0.12; bb = 0.16;
    }
    draw_quad_2d(app, bar_x, cy, 0.006, 0.007, br, bg, bb);
    bar_x = bar_x + 0.010;
    bar_i = bar_i + 1;
  }

  // Numeric FPS
  let num_hw = 0.003;
  let num_x = fx + 0.100;

  // Hundreds digit
  let h = g_fps / 100;
  if h == 0 { draw_quad_2d(app, num_x, cy, num_hw, 0.005, 0.08, 0.08, 0.10); }
  elif h == 1 { draw_quad_2d(app, num_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  elif h == 2 { draw_quad_2d(app, num_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  elif h == 3 { draw_quad_2d(app, num_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  else { draw_quad_2d(app, num_x, cy, num_hw, 0.005, 0.50, 0.15, 0.15); }

  // Tens digit
  let ht = (g_fps - h * 100) / 10;
  let tens_x = num_x + 0.009;
  if ht == 0 { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.08, 0.08, 0.10); }
  elif ht == 1 { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  elif ht == 2 { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  elif ht == 3 { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  elif ht == 4 { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  elif ht == 5 { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.82, 0.55, 0.18); }
  elif ht == 6 { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.82, 0.30, 0.15); }
  elif ht == 7 { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.82, 0.30, 0.15); }
  elif ht == 8 { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.82, 0.30, 0.15); }
  elif ht == 9 { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.82, 0.30, 0.15); }
  else { draw_quad_2d(app, tens_x, cy, num_hw, 0.005, 0.50, 0.15, 0.15); }

  // Ones digit
  let ho = g_fps - h * 100 - ht * 10;
  let ones_x = tens_x + 0.009;
  if ho == 0 { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.08, 0.08, 0.10); }
  elif ho == 1 { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  elif ho == 2 { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  elif ho == 3 { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  elif ho == 4 { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.18, 0.68, 0.35); }
  elif ho == 5 { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.82, 0.55, 0.18); }
  elif ho == 6 { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.82, 0.30, 0.15); }
  elif ho == 7 { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.82, 0.30, 0.15); }
  elif ho == 8 { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.82, 0.30, 0.15); }
  elif ho == 9 { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.82, 0.30, 0.15); }
  else { draw_quad_2d(app, ones_x, cy, num_hw, 0.005, 0.50, 0.15, 0.15); }
}

// ─── Main ───

fn main() -> Int {
  let app = create_app("XIOM Vulkan - Interactive UI Demo", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_frame_count = 0;
      g_last_fps_time = now();
      g_fps = 0;

      while !should_close(a) {
        poll(a);
        let status = begin_frame(a);
        if status == 1 {
          let t = now() as Float32;

          g_frame_count = g_frame_count + 1;
          let nt1 = now(); let nt2 = now();
          let prev_time = g_last_fps_time;
          g_last_fps_time = nt2;
          if nt1 - prev_time >= 1.0 {
            g_fps = g_frame_count;
            g_frame_count = 0;
          }

          set_clear_color(a, 0.03, 0.03, 0.05);

          draw_viewport(a, t);
          draw_sidebar(a, t);
          draw_toolbar(a, t);
          draw_statusbar(a, t);

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
