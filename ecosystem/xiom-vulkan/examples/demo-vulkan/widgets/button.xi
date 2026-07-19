// demo-vulkan widget: Button with 3 states, accent strip, label.
// Uses C bridge hit-testing (xvk_button_hit_state) to avoid Float64.

module demo_vulkan.button

use demo_vulkan.core;
use demo_vulkan.theme;

// Quick draw helper — uses vulkan.xi draw_quad_2d wrapper
fn dq(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(g_app, cx, cy, hw, hh, r, g, b);
}

fn hit_btn(cx: Float32, cy: Float32, hw: Float32, hh: Float32) -> Int {
  return unsafe { xvk_button_hit_state(g_app, cx, cy, hw, hh) } as Int;
}

pub fn draw(cx: Float32, cy: Float32, hw: Float32, hh: Float32,
            accent_r: Float32, accent_g: Float32, accent_b: Float32,
            lw: Float32, lh: Float32) -> Bool {
  let s = hit_btn(cx, cy, hw, hh);
  // Colors by state
  var br = TK_BTN_NORMAL_R(); var bg = TK_BTN_NORMAL_G(); var bb = TK_BTN_NORMAL_B();
  if s == 1 { br = TK_BTN_HOVER_R(); bg = TK_BTN_HOVER_G(); bb = TK_BTN_HOVER_B(); }
  if s == 2 { br = TK_BTN_PRESS_R(); bg = TK_BTN_PRESS_G(); bb = TK_BTN_PRESS_B(); }

  // Body
  dq(cx, cy, hw, hh, br, bg, bb);
  // Top highlight
  dq(cx, cy + hh - 0.001, hw*0.96, 0.0015, br+0.08, bg+0.08, bb+0.10);
  // Bottom shadow
  dq(cx, cy - hh + 0.001, hw*0.96, 0.0015, br-0.04, bg-0.04, bb-0.05);
  // Accent strip
  let sh = hh * 0.12; if sh < 0.002 { sh = 0.002; }
  dq(cx, cy - hh + sh + 0.001, hw*0.88, sh, accent_r, accent_g, accent_b);
  // Label
  if lw > 0.001 && lh > 0.0005 {
    dq(cx, cy + hh*0.06, lw, lh, TK_TEXT_PRIMARY_R(), TK_TEXT_PRIMARY_G(), TK_TEXT_PRIMARY_B());
  }
  return s == 1 && !is_mouse_down(g_app, 0);
}
