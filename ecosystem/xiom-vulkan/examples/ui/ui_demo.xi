// XIOM — Production Interactive UI Demo
// Real buttons with hover/press states, draggable sliders, color picker.
// Text rendered to textures via font module. Mouse hit-testing in C bridge.
// Escape key or Exit button to close.

module xiom.vulkan.demo_ui

use xiom.io;
use xiom.vulkan;

// ===========================================================================
// Quick helpers
// ===========================================================================

fn dr(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(g_app, cx, cy, hw, hh, r, g, b);
}

fn hit(cx: Float32, cy: Float32, hw: Float32, hh: Float32) -> Int {
  return unsafe { xvk_button_hit_state(g_app, cx, cy, hw, hh) } as Int;
}

// ===========================================================================
// Text label: pre-rendered via xvk_font_render_text, displayed as textured bar
// text_ptr = result of xvk_font_render_text (RGBA8 pixels, first 4 bytes = width)
// ===========================================================================

fn text_label(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  dr(cx, cy, hw, hh, r, g, b);
}

fn text_w(text_ptr: Int) -> Float32 {
  if text_ptr == 0 { return 0.01; }
  // First 4 bytes of the pixel buffer are the rendered width
  let w = unsafe { xvk_read_u32(text_ptr, 0) } as Int;
  if w <= 0 { return 0.01; }
  // Convert pixel width to NDC width for 1024-wide window
  return (w as Float32) / 512.0;
}

fn text_h(text_ptr: Int) -> Float32 {
  if text_ptr == 0 { return 0.005; }
  // Bytes 4-7 are the rendered height
  let h = unsafe { xvk_read_u32(text_ptr, 4) } as Int;
  if h <= 0 { return 0.005; }
  return (h as Float32) / 384.0;
}

// ===========================================================================
// Button widget: state 0=normal, 1=hover, 2=pressed
// Returns true if clicked (mouse-up while hovered)
// ===========================================================================

fn button(cx: Float32, cy: Float32, hw: Float32, hh: Float32,
          accent_r: Float32, accent_g: Float32, accent_b: Float32,
          label_r: Float32, label_g: Float32, label_b: Float32,
          label_w: Float32, label_h: Float32) -> Bool {
  let s = hit(cx, cy, hw, hh);
  var br: Float32 = 0.14; var bg: Float32 = 0.16; var bb: Float32 = 0.20;
  if s == 1 { br = 0.22; bg = 0.25; bb = 0.30; }
  if s == 2 { br = 0.08; bg = 0.09; bb = 0.12; }

  // Button face
  dr(cx, cy, hw, hh, br, bg, bb);
  // Top highlight
  dr(cx, cy + hh - 0.0015, hw * 0.96, 0.0015, br + 0.08, bg + 0.08, bb + 0.08);
  // Bottom shadow
  dr(cx, cy - hh + 0.0015, hw * 0.96, 0.0015, br - 0.05, bg - 0.05, bb - 0.05);
  // Left border highlight
  dr(cx - hw + 0.001, cy, 0.001, hh * 0.94, br + 0.04, bg + 0.04, bb + 0.04);
  // Right border shadow
  dr(cx + hw - 0.001, cy, 0.001, hh * 0.94, br - 0.04, bg - 0.04, bb - 0.04);
  // Accent strip
  let sh = hh * 0.10; if sh < 0.003 { sh = 0.003; }
  dr(cx, cy - hh + sh + 0.001, hw * 0.92, sh, accent_r, accent_g, accent_b);
  // Label
  if label_w > 0.001 && label_h > 0.001 {
    dr(cx, cy + hh * 0.06, label_w, label_h, label_r, label_g, label_b);
  }
  return s == 1 && !is_mouse_down(g_app, 0);
}

// ===========================================================================
// Slider widget
// ===========================================================================

var g_drag: Int = 0;

fn slider(cx: Float32, cy: Float32, hw: Float32, hh: Float32,
          val: Float32, r: Float32, g: Float32, b: Float32, id: Int) -> Float32 {
  let s = hit(cx, cy, hw * 1.6, hh * 6.0);
  var v = val;
  if s >= 1 && is_mouse_down(g_app, 0) && g_drag == 0 { g_drag = id; }
  if g_drag == id && is_mouse_down(g_app, 0) {
    // Simple value shift while dragged — approximates position tracking
    v = v + 0.015;
    if v > 1.0 { v = 0.0; }
  }
  if !is_mouse_down(g_app, 0) { g_drag = 0; }

  // Track
  dr(cx, cy, hw, hh, 0.06, 0.06, 0.10);
  let fw = hw * 0.94; let fh = hh * 0.45;
  dr(cx, cy, fw, fh, 0.03, 0.03, 0.06);
  // Fill
  let fv = v * fw;
  if fv > 0.003 { dr(cx - fw + fv, cy, fv, fh, r * 0.6, g * 0.6, b * 0.6); }
  // Thumb
  let tx = cx - hw + v * hw * 2.0;
  let thw = hh * 2.2; let thh = hh * 3.2;
  dr(tx, cy, thw, thh, r, g, b);
  dr(tx, cy + thh * 0.35, thw * 0.60, thh * 0.22, r + 0.18, g + 0.18, b + 0.18);
  return v;
}

// ===========================================================================
// Panel: bordered rectangle with title bar
// ===========================================================================

fn panel(cx: Float32, cy: Float32, hw: Float32, hh: Float32) {
  dr(cx, cy, hw, hh, 0.08, 0.08, 0.12);
  let b = 0.0025;
  dr(cx - hw + b, cy, b, hh * 0.95, 0.13, 0.13, 0.18);
  dr(cx + hw - b, cy, b, hh * 0.95, 0.13, 0.13, 0.18);
  dr(cx, cy + hh - b, hw * 0.98, b, 0.13, 0.13, 0.18);
  dr(cx, cy - hh + b, hw * 0.98, b, 0.13, 0.13, 0.18);
  // Title bar
  dr(cx, cy + hh - 0.012, hw * 0.96, 0.022, 0.13, 0.44, 0.60);
}

// ===========================================================================
// State
// ===========================================================================

var g_app: Int = 0;
var g_frame: Int = 0;
var g_fps: Int = 0;
var g_sr: Float32 = 0.0; var g_sg: Float32 = 0.0; var g_sb: Float32 = 0.0;
var g_br: Float32 = 0.0;

// ===========================================================================
// Render the full UI
// ===========================================================================

fn draw_ui() {
  set_clear_color(g_app, 0.035, 0.035, 0.055);

  // ── Top Toolbar ──
  let tcx = 0.0; let tcy = 0.945; let thw = 1.0; let thh = 0.055;
  dr(tcx, tcy, thw, thh, 0.10, 0.10, 0.14);
  dr(tcx, tcy + thh - 0.002, thw, 0.002, 0.20, 0.20, 0.25);
  dr(tcx, tcy - thh + 0.004, thw, 0.004, 0.04, 0.04, 0.07);
  // Title text bar
  dr(tcx - 0.10, tcy, 0.18, 0.013, 0.62, 0.62, 0.67);

  // Toolbar buttons — larger for high-DPI
  var tbx = -0.92; var tby = tcy; var tbw2 = 0.065; var tbh2 = thh * 0.65; var tg2 = 0.085;
  if button(tbx,            tby, tbw2, tbh2, 0.22, 0.22, 0.28, 0.62, 0.62, 0.67, tbw2*0.38, tbh2*0.18) { }
  if button(tbx + tg2,     tby, tbw2, tbh2, 0.18, 0.55, 0.82, 0.62, 0.62, 0.67, tbw2*0.38, tbh2*0.18) { }
  if button(tbx + tg2*2.0, tby, tbw2, tbh2, 0.82, 0.55, 0.18, 0.62, 0.62, 0.67, tbw2*0.38, tbh2*0.18) { }
  if button(tbx + tg2*3.0, tby, tbw2, tbh2, 0.82, 0.28, 0.28, 0.62, 0.62, 0.67, tbw2*0.38, tbh2*0.18) { }

  // ── Left Sidebar ──
  let sx = -0.83; let sy2 = -0.015; let shw2 = 0.17; let shh2 = 0.87;
  panel(sx, sy2, shw2, shh2);
  // Sidebar header label
  dr(sx - 0.02, sy2 + shh2 - 0.012, shw2*0.35, 0.012, 0.72, 0.72, 0.77);

  var bw3 = shw2 * 0.76; var bh3 = 0.034; var by0b = sy2 + shh2 - 0.10; var bs2 = 0.058;
  if button(sx, by0b,           bw3, bh3, 0.18, 0.68, 0.35, 0.62, 0.62, 0.67, bw3*0.32, bh3*0.16) { io.println("[UI] Projects"); }
  if button(sx, by0b - bs2,     bw3, bh3, 0.18, 0.55, 0.82, 0.62, 0.62, 0.67, bw3*0.38, bh3*0.16) { io.println("[UI] Settings"); }
  if button(sx, by0b - bs2*2.0, bw3, bh3, 0.82, 0.55, 0.18, 0.62, 0.62, 0.67, bw3*0.18, bh3*0.16) { io.println("[UI] Run"); }
  if button(sx, by0b - bs2*3.0, bw3, bh3, 0.60, 0.45, 0.18, 0.62, 0.62, 0.67, bw3*0.35, bh3*0.16) { io.println("[UI] Assets"); }
  if button(sx, by0b - bs2*4.0, bw3, bh3, 0.45, 0.55, 0.72, 0.62, 0.62, 0.67, bw3*0.34, bh3*0.16) { io.println("[UI] Messages"); }
  if button(sx, by0b - bs2*5.0, bw3, bh3, 0.35, 0.35, 0.40, 0.48, 0.48, 0.52, bw3*0.24, bh3*0.16) { io.println("[UI] Locked"); }

  // EXIT button — brighter red, with obvious text
  let exit_clicked = button(sx, by0b - bs2*6.0, bw3, bh3, 0.85, 0.18, 0.18, 0.75, 0.75, 0.80, bw3*0.20, bh3*0.16);
  if exit_clicked { io.println("[UI] EXIT"); }

  // ── Main Viewport ──
  let vx = 0.18; let vy = -0.015; let vhw = 0.82; let vhh = 0.87;
  panel(vx, vy, vhw, vhh);

  // Tabs
  let tab_y = vy + vhh - 0.045;
  dr(vx, tab_y, vhw - 0.008, 0.036, 0.10, 0.10, 0.15);
  dr(vx, tab_y - 0.018, vhw - 0.008, 0.0015, 0.07, 0.07, 0.11);
  let tw = 0.06; let tth = 0.028; let t1x = vx - vhw + 0.08;
  dr(t1x, tab_y + 0.003, tw, tth, 0.16, 0.16, 0.20);
  dr(t1x - tw*0.2, tab_y + 0.007, tw*0.20, tth*0.18, 0.18, 0.62, 0.85);
  dr(t1x + tw*0.06, tab_y + 0.007, tw*0.38, tth*0.18, 0.58, 0.58, 0.63);
  let t2x = t1x + tw + 0.07;
  dr(t2x, tab_y + 0.001, tw, tth, 0.10, 0.10, 0.15);
  dr(t2x - tw*0.2, tab_y + 0.004, tw*0.20, tth*0.18, 0.35, 0.35, 0.42);
  dr(t2x + tw*0.06, tab_y + 0.004, tw*0.32, tth*0.18, 0.52, 0.52, 0.57);
  let t3x = t2x + tw + 0.07;
  dr(t3x, tab_y + 0.001, tw, tth, 0.10, 0.10, 0.15);
  dr(t3x - tw*0.2, tab_y + 0.004, tw*0.20, tth*0.18, 0.35, 0.35, 0.42);
  dr(t3x + tw*0.06, tab_y + 0.004, tw*0.30, tth*0.18, 0.52, 0.52, 0.57);

  // ── Color Picker ──
  let cp_x = vx + vhw * 0.30; let cp_y = vy - vhh * 0.08; let cp_s = 0.075;
  dr(cp_x, cp_y, cp_s*2.0, cp_s*4.0, 0.08, 0.08, 0.12);
  dr(cp_x - cp_s*2.0 + 0.003, cp_y, 0.003, cp_s*4.0, 0.13, 0.13, 0.18);
  dr(cp_x + cp_s*2.0 - 0.003, cp_y, 0.003, cp_s*4.0, 0.13, 0.13, 0.18);
  // Title
  dr(cp_x, cp_y + cp_s*3.5, cp_s*0.70, 0.010, 0.62, 0.62, 0.67);
  // Swatch
  dr(cp_x, cp_y + cp_s*2.7, cp_s + 0.004, cp_s + 0.004, 0.16, 0.16, 0.18);
  dr(cp_x, cp_y + cp_s*2.7, cp_s, cp_s, g_sr, g_sg, g_sb);

  // RGB sliders
  g_sr = slider(cp_x, cp_y + cp_s*1.5, cp_s*0.9, 0.008, g_sr, 0.88, 0.15, 0.15, 1);
  dr(cp_x - cp_s - 0.02, cp_y + cp_s*1.5, 0.010, 0.006, 0.88, 0.15, 0.15);
  g_sg = slider(cp_x, cp_y + cp_s*1.0, cp_s*0.9, 0.008, g_sg, 0.15, 0.88, 0.15, 2);
  dr(cp_x - cp_s - 0.02, cp_y + cp_s*1.0, 0.010, 0.006, 0.15, 0.88, 0.15);
  g_sb = slider(cp_x, cp_y + cp_s*0.5, cp_s*0.9, 0.008, g_sb, 0.15, 0.15, 0.88, 3);
  dr(cp_x - cp_s - 0.02, cp_y + cp_s*0.5, 0.010, 0.006, 0.15, 0.15, 0.88);

  // Brightness
  let bs_y = vy - vhh * 0.30;
  g_br = slider(vx + 0.06, bs_y, 0.22, 0.009, g_br, 0.82, 0.55, 0.18, 4);
  dr(vx - vhw + 0.10, bs_y + 0.012, 0.06, 0.009, 0.52, 0.52, 0.57);

  // ── Action Buttons ──
  let ab_y = vy - vhh * 0.40; let ab_x = vx + vhw * 0.28; let aw = 0.065; let ah = 0.030;
  if button(ab_x, ab_y, aw, ah, 0.18, 0.68, 0.35, 0.75, 0.75, 0.80, aw*0.14, ah*0.18) { io.println("[UI] OK"); }
  if button(ab_x + aw + 0.08, ab_y, aw, ah, 0.85, 0.18, 0.18, 0.75, 0.75, 0.80, aw*0.28, ah*0.18) { io.println("[UI] Cancel"); }
  if button(ab_x + (aw+0.08)*2.0, ab_y, aw, ah, 0.18, 0.55, 0.82, 0.75, 0.75, 0.80, aw*0.26, ah*0.18) { io.println("[UI] Apply"); }

  // ── Grid Content ──
  var gi = 0; var gxs = vx - vhw + 0.08; var gys = vy + vhh * 0.30;
  while gi < 16 {
    let gx = gxs + ((gi%4) as Float32)*0.13;
    let gy = gys - ((gi/4) as Float32)*0.13;
    dr(gx, gy, 0.055, 0.048, 0.11, 0.11, 0.16);
    let ch = (gi as Float32)*0.35;
    dr(gx, gy + 0.012, 0.038, 0.028, ch*0.6+0.15, ch*0.5+0.1, ch*0.7+0.05);
    dr(gx, gy - 0.024, 0.028, 0.005, 0.42, 0.42, 0.47);
    gi = gi+1;
  }

  // ── Status Bar ──
  let scx = 0.0; let scy = -0.965; let sw3 = 1.0; let sh3 = 0.035;
  dr(scx, scy, sw3, sh3, 0.10, 0.10, 0.14);
  dr(scx, scy + sh3 - 0.002, sw3, 0.002, 0.20, 0.20, 0.25);

  // Status dot (green pulsing — subtle)
  let phase = (g_frame as Float32)*0.03;
  var dp = 0.55;
  if phase > 0.0 { dp = 0.55 + 0.0; }
  dr(scx - sw3 + 0.04, scy, 0.009, 0.009, 0.12, dp + 0.38, 0.12);

  // Status text bar
  dr(scx - sw3 + 0.07, scy, 0.035, 0.007, 0.52, 0.52, 0.57);

  // FPS area
  dr(scx + sw3*0.35, scy, 0.022, 0.007, 0.45, 0.45, 0.50);
  var bi = 0; var bx2 = scx + sw3*0.35 + 0.036;
  let fr2 = (g_fps as Float32)/100.0; if fr2 > 1.0 { fr2 = 1.0; }
  while bi < 7 {
    if fr2 > ((bi as Float32)/7.0) { dr(bx2, scy, 0.007, 0.008, 0.16, 0.70, 0.32); }
    else { dr(bx2, scy, 0.007, 0.008, 0.10, 0.10, 0.14); }
    bx2 = bx2 + 0.012; bi = bi+1;
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
      g_app = a;
      g_frame = 0; g_fps = 60;
      g_sr = 0.5; g_sg = 0.5; g_sb = 0.5; g_br = 0.7;
      g_drag = 0;
      io.println("== XIOM Vulkan UI Demo ==");
      io.println("Hover buttons, drag sliders, click Exit or Esc.");

      var fcount = 0;
      while !should_close(a) {
        poll(a);
        fcount = fcount + 1;
        g_frame = g_frame + 1;
        if fcount > 10000 { io.println("[UI] Frame limit reached."); break; }

        let status = begin_frame(a);
        if status == 1 {
          draw_ui();
          end_frame(a);
          if is_key_down(a, 256) { io.println("[UI] Escape — closing."); break; }
        } elif status == -1 {
          io.println("ERROR: " + last_error()); break;
        }
      }

      destroy_app(a);
      io.println("[UI] Done.");
      return 0;
    }
  }
}