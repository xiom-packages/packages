// demo-vulkan panel: Left sidebar — scene/asset browser

module demo_vulkan.sidebar_left

use demo_vulkan.core;
use demo_vulkan.theme;
use demo_vulkan.button;
use demo_vulkan.label;
use demo_vulkan.panel;

pub fn draw() {
  let cx = TK_LAYOUT_LEFT_CX(); let cy = TK_LAYOUT_LEFT_CY();
  let hw = TK_LAYOUT_LEFT_HW(); let hh = TK_LAYOUT_PANEL_HH();
  panel.draw(cx, cy, hw, hh, hw*0.40, 0.012);

  // Category buttons
  var bw = hw*0.75; var bh = 0.032; var by0 = cy + hh - 0.10; var bs = 0.054;
  if button.draw(cx, by0,           bw, bh, TK_ACCENT_1_R(), TK_ACCENT_1_G(), TK_ACCENT_1_B(), bw*0.40, bh*0.16) { core.log("[VK] Triangle"); }
  if button.draw(cx, by0 - bs,      bw, bh, TK_ACCENT_1_R(), TK_ACCENT_1_G(), TK_ACCENT_1_B(), bw*0.38, bh*0.16) { core.log("[VK] Cubes"); }
  if button.draw(cx, by0 - bs*2.0,  bw, bh, TK_ACCENT_2_R(), TK_ACCENT_2_G(), TK_ACCENT_2_B(), bw*0.42, bh*0.16) { core.log("[VK] Particles"); }
  if button.draw(cx, by0 - bs*3.0,  bw, bh, TK_ACCENT_3_R(), TK_ACCENT_3_G(), TK_ACCENT_3_B(), bw*0.38, bh*0.16) { core.log("[VK] Sprites"); }
  if button.draw(cx, by0 - bs*4.0,  bw, bh, TK_ACCENT_2_R(), TK_ACCENT_2_G(), TK_ACCENT_2_B(), bw*0.32, bh*0.16) { core.log("[VK] Mesh"); }
  if button.draw(cx, by0 - bs*5.0,  bw, bh, TK_ACCENT_1_R(), TK_ACCENT_1_G(), TK_ACCENT_1_B(), bw*0.36, bh*0.16) { core.log("[VK] Compute"); }

  // Separator
  let sep_y = by0 - bs*6.0 - 0.012;
  draw_quad_2d(core.g_app, cx, sep_y, hw*0.75, 0.003, 0.12, 0.44, 0.60);
}
