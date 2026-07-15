// XIOM - Immediate-Mode UI Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates a simple immediate-mode UI system over the 2D quad API:
// buttons, sliders, panels, and text labels. Uses the xvk bridge.

module xiom.vulkan.demo_ui

use xiom.io;
use xiom.math;
use xiom.vulkan;

fn draw_button(app: Int, x: Float32, y: Float32, w: Float32, h: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(app, x, y, w, h, r, g, b);
}

fn draw_panel(app: Int, x: Float32, y: Float32, w: Float32, h: Float32) {
  draw_quad_2d(app, x, y, w, h, 0.08, 0.08, 0.12);
  draw_quad_2d(app, x, y, w - 0.01, h - 0.01, 0.04, 0.04, 0.06);
}

fn draw_slider(app: Int, x: Float32, y: Float32, w: Float32, value: Float32) {
  draw_quad_2d(app, x, y, w, 0.02, 0.1, 0.1, 0.15);
  let knob_x = x - w + (value * w * 2.0);
  draw_quad_2d(app, knob_x, y, 0.015, 0.03, 0.2, 0.5, 0.8);
}

pub fn ui_color_picker(app: Int, x: Float32, y: Float32, t: Float32) {
  let r = (math.sin(t) * 0.5 + 0.5) as Float32;
  let g = (math.sin(t + 2.1) * 0.5 + 0.5) as Float32;
  let b = (math.sin(t + 4.2) * 0.5 + 0.5) as Float32;
  // Color preview swatch
  draw_quad_2d(app, x, y, 0.05, 0.05, r, g, b);
  // RGB labels
  draw_quad_2d(app, x - 0.1, y + 0.06, 0.04, 0.008, r, 0.0, 0.0);
  draw_quad_2d(app, x - 0.1, y + 0.04, 0.04, 0.008, 0.0, g, 0.0);
  draw_quad_2d(app, x - 0.1, y + 0.02, 0.04, 0.008, 0.0, 0.0, b);
}

pub fn ui_toolbar(app: Int, x: Float32, y: Float32, t: Float32) {
  var bx = x - 0.6;
  var items: Int = 0;
  while items < 6 {
    let hue = (t + (items as Float32) * 1.05) as Float32;
    let ir = (math.sin(hue as Float64) * 0.4 + 0.5) as Float32;
    let ig = (math.sin((hue + 2.1) as Float64) * 0.4 + 0.5) as Float32;
    let ib = (math.sin((hue + 4.2) as Float64) * 0.4 + 0.5) as Float32;
    draw_button(app, bx, y, 0.04, 0.04, ir, ig, ib);
    bx = bx + 0.1;
    items = items + 1;
  }
}

fn main() -> Int {
  let app = create_app("XIOM Vulkan - UI Demo", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      while !should_close(a) {
        poll(a);
        let status = begin_frame(a);
        if status == 1 {
          let t = now() as Float32;
          set_clear_color(a, 0.02, 0.02, 0.05);

          // Main panel background
          draw_panel(a, 0.0, 0.0, 0.9, 0.85);

          // Toolbar at top
          ui_toolbar(a, 0.0, 0.35, t);

          // Color picker on the right
          ui_color_picker(a, 0.42, 0.25, t);

          // Slider widgets on the left
          var slider_val = (math.sin(t as Float64) * 0.5 + 0.5) as Float32;
          draw_slider(a, -0.3, 0.1, 0.2, slider_val);
          draw_slider(a, -0.3, 0.0, 0.2, slider_val * 0.7);
          draw_slider(a, -0.3, -0.1, 0.2, slider_val * 0.4);

          // Some buttons
          draw_button(a, -0.4, -0.25, 0.06, 0.05, 0.2, 0.6, 0.2);
          draw_button(a, -0.3, -0.25, 0.06, 0.05, 0.6, 0.2, 0.2);
          draw_button(a, -0.2, -0.25, 0.06, 0.05, 0.2, 0.2, 0.6);

          end_frame(a);
        } elif status == -1 { break; }
      }
      destroy_app(a);
      return 0;
    }
  }
}
