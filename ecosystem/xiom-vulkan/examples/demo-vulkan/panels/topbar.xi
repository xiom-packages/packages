// demo-vulkan panel: Top menu bar

module demo_vulkan.topbar

use demo_vulkan.core;
use demo_vulkan.theme;
use demo_vulkan.button;
use demo_vulkan.label;

pub fn draw() {
  let cx = 0.0; let cy = TK_LAYOUT_TOPBAR_CY(); let hw = 1.0; let hh = TK_LAYOUT_TOPBAR_HH();
  draw_quad_2d(g_app, cx, cy, hw, hh, 0.10, 0.10, 0.14);
  draw_quad_2d(g_app, cx, cy + hh - 0.002, hw, 0.002, 0.22, 0.22, 0.26);
  draw_quad_2d(g_app, cx, cy - hh + 0.004, hw, 0.004, 0.04, 0.04, 0.07);

  // Title label
  label.draw(cx - 0.15, cy, 0.25, 0.014, TK_TEXT_PRIMARY_R(), TK_TEXT_PRIMARY_G(), TK_TEXT_PRIMARY_B());

  // Menu buttons
  var bx = -0.92; var by = cy; var bw = 0.06; var bh = hh * 0.65; var gap = 0.075;
  if button.draw(bx, by, bw, bh, TK_ACCENT_1_R(), TK_ACCENT_1_G(), TK_ACCENT_1_B(), bw*0.30, bh*0.18) { }
  if button.draw(bx+gap, by, bw, bh, TK_ACCENT_2_R(), TK_ACCENT_2_G(), TK_ACCENT_2_B(), bw*0.30, bh*0.18) { }
  if button.draw(bx+gap*2.0, by, bw, bh, TK_ACCENT_3_R(), TK_ACCENT_3_G(), TK_ACCENT_3_B(), bw*0.18, bh*0.18) { }
  if button.draw(bx+gap*3.0, by, bw, bh, TK_ACCENT_DANGER_R(), TK_ACCENT_DANGER_G(), TK_ACCENT_DANGER_B(), bw*0.18, bh*0.18) { core.g_exit = 1; }
}
