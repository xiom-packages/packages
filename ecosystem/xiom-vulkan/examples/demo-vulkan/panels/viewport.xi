// demo-vulkan panel: 3D viewport

module demo_vulkan.viewport

use demo_vulkan.core;
use demo_vulkan.theme;
use demo_vulkan.panel;

var g_angle: Float32 = 0.0;
var g_vp_mode: Int = 0;

pub fn init() {
  g_angle = 0.0; g_vp_mode = 0;
}

pub fn draw() {
  let cx = TK_LAYOUT_VIEWPORT_CX(); let cy = TK_LAYOUT_VIEWPORT_CY();
  let hw = TK_LAYOUT_VIEWPORT_HW(); let hh = TK_LAYOUT_PANEL_HH();
  panel.draw(cx, cy, hw, hh, hw*0.30, 0.012);

  // Increment rotation angle
  g_angle = g_angle + 0.02;
  if g_angle > 6.28 { g_angle = 0.0; }

  // Draw rotating 3D cube as background content
  draw_cube_3d_at(core.g_app, g_angle, 0.0, -0.15, -2.0, 0.35);
  // Draw a second cube offset
  draw_cube_3d_at(core.g_app, g_angle + 1.5, 0.35, -0.25, -2.5, 0.22);
  // Small cube in corner
  draw_cube_3d_at(core.g_app, g_angle + 0.8, -0.3, -0.1, -1.8, 0.15);
}
