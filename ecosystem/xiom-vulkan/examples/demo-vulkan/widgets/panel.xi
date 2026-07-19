// demo-vulkan widget: Panel — bordered container with title bar

module demo_vulkan.panel

use demo_vulkan.core;
use demo_vulkan.theme;

fn dq(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(g_app, cx, cy, hw, hh, r, g, b);
}

pub fn draw(cx: Float32, cy: Float32, hw: Float32, hh: Float32, title_w: Float32, title_h: Float32) {
  // Panel fill
  dq(cx, cy, hw, hh, TK_PANEL_BG_R(), TK_PANEL_BG_G(), TK_PANEL_BG_B());
  // Borders
  let bw = TK_BORDER_W();
  dq(cx - hw + bw, cy, bw, hh*0.96, TK_PANEL_BORDER_R(), TK_PANEL_BORDER_G(), TK_PANEL_BORDER_B());
  dq(cx + hw - bw, cy, bw, hh*0.96, TK_PANEL_BORDER_R(), TK_PANEL_BORDER_G(), TK_PANEL_BORDER_B());
  dq(cx, cy + hh - bw, hw*0.96, bw, TK_PANEL_BORDER_R(), TK_PANEL_BORDER_G(), TK_PANEL_BORDER_B());
  dq(cx, cy - hh + bw, hw*0.96, bw, TK_PANEL_BORDER_R(), TK_PANEL_BORDER_G(), TK_PANEL_BORDER_B());
  // Title bar
  let th = TK_TITLE_H();
  dq(cx, cy + hh - th*0.5, hw*0.92, th, TK_ACCENT_1_R()*0.7, TK_ACCENT_1_G()*0.7, TK_ACCENT_1_B()*0.7);
  // Title label
  if title_w > 0.001 && title_h > 0.0005 {
    dq(cx - hw + 0.02, cy + hh - th*0.5, title_w, title_h, TK_TEXT_PRIMARY_R(), TK_TEXT_PRIMARY_G(), TK_TEXT_PRIMARY_B());
  }
}
