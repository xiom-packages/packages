// demo-vulkan widget: Slider with draggable thumb

module demo_vulkan.slider

use demo_vulkan.core;
use demo_vulkan.theme;

var g_drag: Int = 0;

fn dq(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(g_app, cx, cy, hw, hh, r, g, b);
}

fn hit2(cx: Float32, cy: Float32, hw: Float32, hh: Float32) -> Int {
  return unsafe { xvk_button_hit_state(g_app, cx, cy, hw, hh) } as Int;
}

pub fn draw(cx: Float32, cy: Float32, hw: Float32, hh: Float32,
            val: Float32, tr: Float32, tg: Float32, tb: Float32, id: Int) -> Float32 {
  let s = hit2(cx, cy, hw*1.6, hh*5.0);
  var v = val;
  if s >= 1 && is_mouse_down(g_app, 0) && g_drag == 0 { g_drag = id; }
  if g_drag == id && is_mouse_down(g_app, 0) {
    v = v + 0.015; if v > 1.0 { v = 0.0; }
  }
  if !is_mouse_down(g_app, 0) { g_drag = 0; }

  // Track groove
  dq(cx, cy, hw, hh, 0.06, 0.06, 0.10);
  // Inner track
  let fw = hw * 0.94; let fh = hh * 0.45;
  dq(cx, cy, fw, fh, 0.03, 0.03, 0.06);
  // Fill
  let fv = v * fw;
  if fv > 0.003 { dq(cx - fw + fv, cy, fv, fh, tr*0.6, tg*0.6, tb*0.6); }
  // Thumb
  let tx = cx - hw + v * hw * 2.0;
  let thw = hh * 2.2; let thh = hh * 3.2;
  dq(tx, cy, thw, thh, tr, tg, tb);
  dq(tx, cy + thh*0.35, thw*0.60, thh*0.22, tr + 0.18, tg + 0.18, tb + 0.18);
  return v;
}
