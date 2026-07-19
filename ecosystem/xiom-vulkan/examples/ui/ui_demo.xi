// XIOM — Production-Grade Interactive UI Demo
// Buttons: hover/press states, sliders: draggable, color picker, exit button.
// Mouse hit-testing in C via xvk_button_hit_state (avoids CG-01 Float64 bug).
//
// Build: xiomc -o ui_demo.exe examples/ui/ui_demo.xi vulkan.xi src/wrapper.xi
//   --c-source bridge/xvk_bridge.obj --link vulkan-1 --link glfw3 ...

module xiom.vulkan.demo_ui

use xiom.io;
use xiom.vulkan;

// ===========================================================================
// Draw helpers
// ===========================================================================

fn dr(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(g_app, cx, cy, hw, hh, r, g, b);
}

fn hit(cx: Float32, cy: Float32, hw: Float32, hh: Float32) -> Int {
  return unsafe { xvk_button_hit_state(g_app, cx, cy, hw, hh) } as Int;
}

// ===========================================================================
// Button: interactive with hover(1)/press(2)/normal(0) states
// Returns true on click (mouse-up while inside)
// ===========================================================================

fn button(cx: Float32, cy: Float32, hw: Float32, hh: Float32,
          ar: Float32, ag: Float32, ab: Float32) -> Bool {
  let s = hit(cx, cy, hw, hh);
  var br: Float32 = 0.14; var bg: Float32 = 0.16; var bb: Float32 = 0.20;
  if s == 1 { br = 0.20; bg = 0.23; bb = 0.28; }
  if s == 2 { br = 0.10; bg = 0.11; bb = 0.14; }
  dr(cx, cy, hw, hh, br, bg, bb);
  dr(cx, cy + hh - 0.001, hw, 0.001, br+0.06, bg+0.06, bb+0.06);
  dr(cx, cy - hh + 0.001, hw, 0.001, br-0.04, bg-0.04, bb-0.04);
  let sh = hh * 0.12; if sh < 0.002 { sh = 0.002; }
  dr(cx, cy - hh + sh, hw - 0.004, sh, ar, ag, ab);
  dr(cx, cy + hh*0.08, hw*0.70, hh*0.16, 0.58, 0.58, 0.63);
  return s == 1 && !is_mouse_down(g_app, 0);
}

// ===========================================================================
// Slider: colored track with draggable thumb
// ===========================================================================

var g_drag: Int = 0;

fn slider(cx: Float32, cy: Float32, hw: Float32, hh: Float32,
          val: Float32, r: Float32, g: Float32, b: Float32, id: Int) -> Float32 {
  var v = val;
  let s = hit(cx, cy, hw*1.5, hh*5.0);
  if s >= 1 && is_mouse_down(g_app, 0) { g_drag = id; }
  if g_drag == id && is_mouse_down(g_app, 0) { v = v + 0.01; if v > 1.0 { v = 0.0; } }
  else { g_drag = 0; }

  dr(cx, cy, hw, hh, 0.06, 0.06, 0.09);
  let fw = hw*0.94; let fh = hh*0.40;
  dr(cx, cy, fw, fh, 0.03, 0.03, 0.05);
  let aw = v * fw;
  if aw > 0.003 { dr(cx-fw+aw, cy, aw, fh, r*0.6, g*0.6, b*0.6); }
  let tx = cx - hw + v*hw*2.0;
  dr(tx, cy, hh*2.5, hh*3.5, r, g, b);
  return v;
}

// ===========================================================================
// Panel: bordered rectangle with title bar
// ===========================================================================

fn panel(cx: Float32, cy: Float32, hw: Float32, hh: Float32) {
  dr(cx, cy, hw, hh, 0.08, 0.08, 0.11);
  let b = 0.002;
  dr(cx-hw+b, cy, b, hh, 0.12, 0.12, 0.16);
  dr(cx+hw-b, cy, b, hh, 0.12, 0.12, 0.16);
  dr(cx, cy+hh-b, hw, b, 0.12, 0.12, 0.16);
  dr(cx, cy-hh+b, hw, b, 0.12, 0.12, 0.16);
  dr(cx, cy+hh-0.009, hw-0.004, 0.018, 0.126, 0.434, 0.595);
}

// ===========================================================================
// Global state (needs to be at module scope for XIOM)
// ===========================================================================

var g_app: Int = 0;
var g_frame: Int = 0;
var g_fps: Int = 0;
var g_sr: Float32 = 0.0; var g_sg: Float32 = 0.0; var g_sb: Float32 = 0.0;
var g_v: Float32 = 0.0;

// ===========================================================================
// Draw the entire UI
// ===========================================================================

fn draw_ui() {
  set_clear_color(g_app, 0.04, 0.04, 0.06);

  // Top Toolbar
  dr(0.0, 0.953, 1.0, 0.047, 0.10, 0.10, 0.13);
  dr(0.0, 0.998, 1.0, 0.002, 0.18, 0.18, 0.22);
  dr(0.0, 0.909, 1.0, 0.003, 0.04, 0.04, 0.06);
  dr(0.0, 0.953, 0.14, 0.010, 0.65, 0.65, 0.70);

  var tbx = -0.93; var tby = 0.953; var tbw = 0.055; var tbh = 0.029; var tg = 0.070;
  if button(tbx,          tby, tbw, tbh, 0.22,0.22,0.26) { }
  if button(tbx + tg,     tby, tbw, tbh, 0.18,0.55,0.82) { }
  if button(tbx + tg*2.0, tby, tbw, tbh, 0.82,0.55,0.18) { }
  if button(tbx + tg*3.0, tby, tbw, tbh, 0.82,0.28,0.28) { }

  // Left Sidebar
  let sx = -0.844; let sy = -0.008; let shw = 0.156; let shh = 0.89;
  panel(sx, sy, shw, shh);
  dr(sx-shw+0.04, sy+shh-0.009, shw*0.35, 0.010, 0.72,0.72,0.76);

  var bw = shw*0.78; var bh = 0.028; var by0 = sy+shh-0.09; var bs = 0.050;
  if button(sx, by0,          bw, bh, 0.18,0.68,0.35) { io.println("Projects"); }
  if button(sx, by0 - bs,     bw, bh, 0.18,0.55,0.82) { io.println("Settings"); }
  if button(sx, by0 - bs*2.0, bw, bh, 0.82,0.55,0.18) { io.println("Run"); }
  if button(sx, by0 - bs*3.0, bw, bh, 0.60,0.45,0.18) { io.println("Assets"); }
  if button(sx, by0 - bs*4.0, bw, bh, 0.45,0.55,0.72) { io.println("Messages"); }
  if button(sx, by0 - bs*5.0, bw, bh, 0.35,0.35,0.40) { io.println("Locked"); }

  // EXIT button
  if button(sx, by0 - bs*6.0, bw, bh, 0.72,0.22,0.22) { io.println("[UI] EXIT"); }

  // Main Viewport
  let vx = 0.16; let vy = -0.008; let vhw = 0.84; let vhh = 0.89;
  panel(vx, vy, vhw, vhh);

  // Tabs
  let tab_y = vy + vhh - 0.045;
  dr(vx, tab_y, vhw-0.01, 0.033, 0.10,0.10,0.14);
  dr(vx, tab_y-0.017, vhw-0.01, 0.001, 0.07,0.07,0.10);
  let tw = 0.055; let thh_tab = 0.026; let t1x = vx - vhw + 0.075;
  dr(t1x, tab_y+0.003, tw, thh_tab, 0.15,0.15,0.19);
  dr(t1x-tw*0.2, tab_y+0.006, tw*0.18, thh_tab*0.16, 0.18,0.62,0.85);
  dr(t1x+tw*0.05, tab_y+0.006, tw*0.35, thh_tab*0.16, 0.58,0.58,0.63);
  let t2x = t1x + tw + 0.06;
  dr(t2x, tab_y+0.001, tw, thh_tab, 0.10,0.10,0.14);
  dr(t2x-tw*0.2, tab_y+0.004, tw*0.18, thh_tab*0.16, 0.35,0.35,0.42);
  dr(t2x+tw*0.05, tab_y+0.004, tw*0.30, thh_tab*0.16, 0.52,0.52,0.57);

  // Color Picker
  let cp_x = vx + vhw*0.30; let cp_y = vy - vhh*0.06; let cp_s = 0.065;
  dr(cp_x, cp_y, cp_s*1.9, cp_s*3.6, 0.08,0.08,0.11);
  dr(cp_x-cp_s*1.9+0.002, cp_y, 0.002, cp_s*3.6, 0.12,0.12,0.16);
  dr(cp_x+cp_s*1.9-0.002, cp_y, 0.002, cp_s*3.6, 0.12,0.12,0.16);
  dr(cp_x, cp_y+cp_s*3.2, cp_s*0.60, 0.008, 0.62,0.62,0.67);
  dr(cp_x, cp_y+cp_s*2.5, cp_s+0.003, cp_s+0.003, 0.16,0.16,0.18);
  dr(cp_x, cp_y+cp_s*2.5, cp_s, cp_s, g_sr, g_sg, g_sb);

  g_sr = slider(cp_x, cp_y+cp_s*1.3, cp_s*0.9, 0.006, g_sr, 0.85,0.15,0.15, 1);
  dr(cp_x-cp_s-0.015, cp_y+cp_s*1.3, 0.008, 0.005, 0.85,0.15,0.15);
  g_sg = slider(cp_x, cp_y+cp_s*0.9, cp_s*0.9, 0.006, g_sg, 0.15,0.85,0.15, 2);
  dr(cp_x-cp_s-0.015, cp_y+cp_s*0.9, 0.008, 0.005, 0.15,0.85,0.15);
  g_sb = slider(cp_x, cp_y+cp_s*0.5, cp_s*0.9, 0.006, g_sb, 0.15,0.15,0.85, 3);
  dr(cp_x-cp_s-0.015, cp_y+cp_s*0.5, 0.008, 0.005, 0.15,0.15,0.85);

  // Brightness
  let bs_y = vy - vhh*0.28;
  g_v = slider(vx+0.04, bs_y, 0.20, 0.007, g_v, 0.82,0.55,0.18, 4);
  dr(vx-vhw+0.09, bs_y+0.010, 0.05, 0.007, 0.52,0.52,0.57);

  // Action buttons
  let ab_y = vy - vhh*0.38; let ab_x = vx + vhw*0.26; let aw = 0.055; let ah = 0.024;
  if button(ab_x, ab_y, aw, ah, 0.18,0.68,0.35) { io.println("[UI] OK"); }
  if button(ab_x+aw+0.07, ab_y, aw, ah, 0.72,0.22,0.22) { io.println("[UI] Cancel"); }
  if button(ab_x+(aw+0.07)*2.0, ab_y, aw, ah, 0.18,0.55,0.82) { io.println("[UI] Apply"); }

  // Grid
  var gi = 0; var gxs = vx-vhw+0.07; var gys = vy+vhh*0.32;
  while gi < 20 {
    let gx = gxs + ((gi%5) as Float32)*0.11;
    let gy = gys - ((gi/5) as Float32)*0.11;
    dr(gx, gy, 0.045, 0.038, 0.11,0.11,0.15);
    let ch = (gi as Float32)*0.3;
    dr(gx, gy+0.010, 0.030, 0.022, ch*0.5+0.2, ch*0.4+0.1, ch*0.6);
    dr(gx, gy-0.020, 0.020, 0.004, 0.42,0.42,0.47);
    gi = gi+1;
  }

  // Status bar
  let scx = 0.0; let scy = -0.969; let sw = 1.0; let sh2 = 0.031;
  dr(scx, scy, sw, sh2, 0.10,0.10,0.13);
  dr(scx, scy+sh2-0.002, sw, 0.002, 0.18,0.18,0.22);
  dr(scx-sw+0.035, scy, 0.007, 0.007, 0.15,0.70,0.15);
  dr(scx-sw+0.06, scy, 0.025, 0.006, 0.55,0.55,0.60);

  // FPS text
  dr(scx+sw*0.33, scy, 0.018, 0.006, 0.45,0.45,0.50);
  let fr = (g_fps as Float32)/120.0; if fr > 1.0 { fr = 1.0; }
  var bi = 0; var bx = scx+sw*0.33+0.035;
  while bi < 6 {
    if fr > ((bi as Float32)/6.0) { dr(bx, scy, 0.006, 0.007, 0.18,0.68,0.35); }
    else { dr(bx, scy, 0.006, 0.007, 0.10,0.10,0.14); }
    bx = bx+0.010; bi = bi+1;
  }
}

// ===========================================================================
// Main
// ===========================================================================

fn main() -> Int {
  let app = create_app("XIOM Vulkan — Production UI Demo", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_app = a; g_frame = 0; g_fps = 0;
      g_sr = 0.5; g_sg = 0.5; g_sb = 0.5; g_v = 0.7;
      io.println("== XIOM Vulkan UI Demo ==");
      io.println("Hover buttons, drag sliders, click Exit or Esc.");

      while !should_close(a) {
        poll(a);
        g_frame = g_frame + 1;

        let status = begin_frame(a);
        if status == 1 {
          draw_ui();
          end_frame(a);
          if is_key_down(a, 256) { io.println("[UI] Escape."); break; }
          if status == -1 { io.println("ERROR: "+last_error()); break; }
        }
      }
      destroy_app(a);
      io.println("[UI] Done.");
      return 0;
    }
  }
}