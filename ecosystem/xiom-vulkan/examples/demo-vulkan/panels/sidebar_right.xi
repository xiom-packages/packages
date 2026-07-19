// demo-vulkan panel: Right sidebar — controls and property inspector

module demo_vulkan.sidebar_right

use demo_vulkan.core;
use demo_vulkan.theme;
use demo_vulkan.button;
use demo_vulkan.slider;
use demo_vulkan.label;
use demo_vulkan.panel;

var g_sr: Float32 = 0.0; var g_sg: Float32 = 0.0; var g_sb: Float32 = 0.0;
var g_br: Float32 = 0.0;

pub fn init() {
  g_sr = 0.6; g_sg = 0.3; g_sb = 0.8; g_br = 0.7;
}

pub fn draw() {
  let cx = TK_LAYOUT_RIGHT_CX(); let cy = TK_LAYOUT_RIGHT_CY();
  let hw = TK_LAYOUT_RIGHT_HW(); let hh = TK_LAYOUT_PANEL_HH();
  panel.draw(cx, cy, hw, hh, hw*0.45, 0.012);

  // Color picker section
  let cp_y = cy + hh - 0.09; let cp_s = 0.04;
  label.draw(cx - hw + 0.02, cp_y, hw*0.30, 0.010, TK_TEXT_PRIMARY_R(), TK_TEXT_PRIMARY_G(), TK_TEXT_PRIMARY_B());

  // Swatch
  draw_quad_2d(core.g_app, cx + 0.015, cp_y - 0.055, cp_s*0.9, cp_s*0.9, 0.12, 0.12, 0.18);
  draw_quad_2d(core.g_app, cx + 0.015, cp_y - 0.055, cp_s*0.8, cp_s*0.8, g_sr, g_sg, g_sb);

  // Sliders
  let scy = cp_y - 0.115;
  g_sr = slider.draw(cx, scy, hw*0.55, 0.007, g_sr, 0.88, 0.15, 0.15, 10);
  label.draw(cx - hw + 0.02, scy, hw*0.08, 0.006, 0.88, 0.15, 0.15);
  g_sg = slider.draw(cx, scy - 0.035, hw*0.55, 0.007, g_sg, 0.15, 0.88, 0.15, 11);
  label.draw(cx - hw + 0.02, scy - 0.035, hw*0.08, 0.006, 0.15, 0.88, 0.15);
  g_sb = slider.draw(cx, scy - 0.07, hw*0.55, 0.007, g_sb, 0.15, 0.15, 0.88, 12);
  label.draw(cx - hw + 0.02, scy - 0.07, hw*0.08, 0.006, 0.15, 0.15, 0.88);

  // Brightness
  let bri_y = scy - 0.12;
  g_br = slider.draw(cx, bri_y, hw*0.55, 0.007, g_br, TK_ACCENT_2_R(), TK_ACCENT_2_G(), TK_ACCENT_2_B(), 13);
  label.draw(cx - hw + 0.02, bri_y, hw*0.30, 0.006, TK_ACCENT_2_R(), TK_ACCENT_2_G(), TK_ACCENT_2_B());

  // Action buttons
  let ab_y = cy - hh + 0.07; let aw = hw*0.38; let ah = 0.028;
  if button.draw(cx, ab_y, aw, ah, TK_ACCENT_3_R(), TK_ACCENT_3_G(), TK_ACCENT_3_B(), aw*0.14, ah*0.18) { core.log("[VK] Apply"); }
  if button.draw(cx, ab_y - 0.045, aw, ah, TK_ACCENT_DANGER_R(), TK_ACCENT_DANGER_G(), TK_ACCENT_DANGER_B(), aw*0.28, ah*0.18) { core.g_exit = 1; }
}
