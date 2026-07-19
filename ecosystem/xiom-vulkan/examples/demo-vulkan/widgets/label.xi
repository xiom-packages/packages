// demo-vulkan widget: Label — colored bar representing text

module demo_vulkan.label

use demo_vulkan.core;

fn dq(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(g_app, cx, cy, hw, hh, r, g, b);
}

pub fn draw(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  if hw > 0.001 && hh > 0.0005 { dq(cx, cy, hw, hh, r, g, b); }
}
