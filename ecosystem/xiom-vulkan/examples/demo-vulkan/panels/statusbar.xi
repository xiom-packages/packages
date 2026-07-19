// demo-vulkan panel: Status bar with FPS and GPU info

module demo_vulkan.statusbar

use demo_vulkan.core;
use demo_vulkan.theme;
use demo_vulkan.label;

pub fn draw() {
  let cx = 0.0; let cy = TK_LAYOUT_STATUSBAR_CY(); let hw = 1.0; let hh = TK_LAYOUT_STATUSBAR_HH();
  draw_quad_2d(core.g_app, cx, cy, hw, hh, 0.10, 0.10, 0.14);
  draw_quad_2d(core.g_app, cx, cy + hh - 0.002, hw, 0.002, 0.22, 0.22, 0.26);

  // Green status dot
  draw_quad_2d(core.g_app, cx - hw + 0.04, cy, 0.008, 0.008, 0.12, 0.65, 0.25);

  // Status text
  label.draw(cx - hw + 0.07, cy, 0.040, 0.008, TK_TEXT_PRIMARY_R(), TK_TEXT_PRIMARY_G(), TK_TEXT_PRIMARY_B());

  // FPS label
  label.draw(cx + hw*0.35, cy, 0.022, 0.008, TK_TEXT_SECONDARY_R(), TK_TEXT_SECONDARY_G(), TK_TEXT_SECONDARY_B());

  // FPS bar graph
  let fr = (core.g_fps as Float32) / 100.0; if fr > 1.0 { fr = 1.0; }
  var bi = 0; var bx = cx + hw*0.35 + 0.034;
  while bi < 8 {
    if fr > ((bi as Float32) / 8.0) {
      draw_quad_2d(core.g_app, bx, cy, 0.007, 0.009, 0.14, 0.68, 0.34);
    } else {
      draw_quad_2d(core.g_app, bx, cy, 0.007, 0.009, 0.08, 0.08, 0.12);
    }
    bx = bx + 0.013;
    bi = bi + 1;
  }

  // GPU info label
  label.draw(cx + hw*0.55, cy, 0.025, 0.008, TK_TEXT_SECONDARY_R(), TK_TEXT_SECONDARY_G(), TK_TEXT_SECONDARY_B());
}
