// XIOM Vulkan Showcase — Production Demo
// Game-style GUI: topbar, left scene browser, right controls, center viewport.
// Interactive buttons, draggable sliders, color picker, exit button.
// Single file (multi-file merge hitting LLVM IR edges in v0.48.2).

module demo_vulkan

use xiom.io;
use xiom.vulkan;

// ── Global state ──
var g_app: Int = 0;
var g_exit: Int = 0;

// ── Quick draw ──
fn rct(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(g_app, cx, cy, hw, hh, r, g, b);
}
fn ht(cx: Float32, cy: Float32, hw: Float32, hh: Float32) -> Int {
  return unsafe { xvk_button_hit_state(g_app, cx, cy, hw, hh) } as Int;
}
fn md() -> Bool { return is_mouse_down(g_app, 0); }

// ── Colors ──
fn C0R() -> Float32 { return 0.04; } fn C0G() -> Float32 { return 0.04; } fn C0B() -> Float32 { return 0.06; }
fn C1R() -> Float32 { return 0.07; } fn C1G() -> Float32 { return 0.08; } fn C1B() -> Float32 { return 0.11; }
fn CBR() -> Float32 { return 0.14; } fn CBG() -> Float32 { return 0.44; } fn CBB() -> Float32 { return 0.60; }
fn BNR() -> Float32 { return 0.12; } fn BNG() -> Float32 { return 0.14; } fn BNB() -> Float32 { return 0.18; }
fn BHR() -> Float32 { return 0.20; } fn BHG() -> Float32 { return 0.24; } fn BHB() -> Float32 { return 0.30; }
fn BPR() -> Float32 { return 0.07; } fn BPG() -> Float32 { return 0.08; } fn BPB() -> Float32 { return 0.11; }
fn A1R() -> Float32 { return 0.16; } fn A1G() -> Float32 { return 0.64; } fn A1B() -> Float32 { return 0.88; }
fn A2R() -> Float32 { return 0.88; } fn A2G() -> Float32 { return 0.55; } fn A2B() -> Float32 { return 0.16; }
fn A3R() -> Float32 { return 0.16; } fn A3G() -> Float32 { return 0.88; } fn A3B() -> Float32 { return 0.55; }
fn ADR() -> Float32 { return 0.88; } fn ADG() -> Float32 { return 0.20; } fn ADB() -> Float32 { return 0.32; }
fn TXR() -> Float32 { return 0.85; } fn TXG() -> Float32 { return 0.85; } fn TXB() -> Float32 { return 0.88; }
fn TMR() -> Float32 { return 0.48; } fn TMG() -> Float32 { return 0.50; } fn TMB() -> Float32 { return 0.55; }

// ── Button: 3 states, accent strip, returns true on click ──
fn btn(cx: Float32, cy: Float32, hw: Float32, hh: Float32,
       ar: Float32, ag: Float32, ab: Float32, lw: Float32, lh: Float32) -> Bool {
  let s = ht(cx, cy, hw, hh);
  var br = BNR(); var bg = BNG(); var bb = BNB();
  if s == 1 { br = BHR(); bg = BHG(); bb = BHB(); }
  if s == 2 { br = BPR(); bg = BPG(); bb = BPB(); }
  rct(cx, cy, hw, hh, br, bg, bb);
  rct(cx, cy + hh - 0.001, hw*0.96, 0.0015, br+0.08, bg+0.08, bb+0.10);
  rct(cx, cy - hh + 0.001, hw*0.96, 0.0015, br-0.04, bg-0.04, bb-0.05);
  let sh = hh * 0.12; if sh < 0.002 { sh = 0.002; }
  rct(cx, cy - hh + sh + 0.001, hw*0.88, sh, ar, ag, ab);
  if lw > 0.001 && lh > 0.0005 { rct(cx, cy + hh*0.06, lw, lh, TXR(), TXG(), TXB()); }
  return s == 1 && !md();
}
fn lbl(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  if hw > 0.001 && hh > 0.0005 { rct(cx, cy, hw, hh, r, g, b); }
}

// ── Panel: bordered container ──
fn pnl(cx: Float32, cy: Float32, hw: Float32, hh: Float32, tw: Float32, th: Float32) {
  rct(cx, cy, hw, hh, C1R(), C1G(), C1B());
  let bw = 0.003;
  rct(cx - hw + bw, cy, bw, hh*0.96, CBR(), CBG(), CBB());
  rct(cx + hw - bw, cy, bw, hh*0.96, CBR(), CBG(), CBB());
  rct(cx, cy + hh - bw, hw*0.96, bw, CBR(), CBG(), CBB());
  rct(cx, cy - hh + bw, hw*0.96, bw, CBR(), CBG(), CBB());
  let tr = 0.025;
  rct(cx, cy + hh - tr*0.5, hw*0.92, tr, A1R()*0.7, A1G()*0.7, A1B()*0.7);
  if tw > 0.001 && th > 0.0005 { rct(cx - hw + 0.02, cy + hh - tr*0.5, tw, th, TXR(), TXG(), TXB()); }
}

// ── Slider ──
var sdr: Int = 0;
fn sld(cx: Float32, cy: Float32, hw: Float32, hh: Float32,
       val: Float32, tr: Float32, tg: Float32, tb: Float32, id: Int) -> Float32 {
  let s = ht(cx, cy, hw*1.6, hh*5.0);
  var v = val;
  if s >= 1 && md() && sdr == 0 { sdr = id; }
  if sdr == id && md() { v = v + 0.015; if v > 1.0 { v = 0.0; } }
  if !md() { sdr = 0; }
  rct(cx, cy, hw, hh, 0.06, 0.06, 0.10);
  let fw = hw*0.94; let fh = hh*0.45;
  rct(cx, cy, fw, fh, 0.03, 0.03, 0.06);
  let fv = v * fw;
  if fv > 0.003 { rct(cx - fw + fv, cy, fv, fh, tr*0.6, tg*0.6, tb*0.6); }
  let tx = cx - hw + v * hw * 2.0;
  rct(tx, cy, hh*2.2, hh*3.2, tr, tg, tb);
  return v;
}

// ── Sidebar right state ──
var sr_r: Float32 = 0.0; var sr_g: Float32 = 0.0; var sr_b: Float32 = 0.0;
var sr_br: Float32 = 0.0;
var vp_angle: Float32 = 0.0;

// ── Top bar ──
fn draw_top() {
  let cy = 0.94; let hh = 0.06;
  rct(0.0, cy, 1.0, hh, 0.10, 0.10, 0.14);
  rct(0.0, cy+hh-0.002, 1.0, 0.002, 0.22, 0.22, 0.26);
  rct(0.0, cy-hh+0.004, 1.0, 0.004, 0.04, 0.04, 0.07);
  lbl(-0.15, cy, 0.25, 0.014, TXR(), TXG(), TXB());
  var bx = -0.92; var bw = 0.06; var bh = hh*0.65; var gap = 0.075;
  if btn(bx, cy, bw, bh, A1R(), A1G(), A1B(), bw*0.30, bh*0.18) { }
  if btn(bx+gap, cy, bw, bh, A2R(), A2G(), A2B(), bw*0.30, bh*0.18) { }
  if btn(bx+gap*2.0, cy, bw, bh, A3R(), A3G(), A3B(), bw*0.18, bh*0.18) { }
  if btn(bx+gap*3.0, cy, bw, bh, ADR(), ADG(), ADB(), bw*0.18, bh*0.18) { g_exit = 1; }
}

// ── Left sidebar ──
fn draw_left() {
  let cx = -0.84; let cy = -0.01; let hw = 0.16; let hh = 0.86;
  pnl(cx, cy, hw, hh, hw*0.40, 0.012);
  var bw = hw*0.75; var bh = 0.032; var by0 = cy+hh-0.10; var bs = 0.054;
  if btn(cx, by0,          bw, bh, A1R(), A1G(), A1B(), bw*0.40, bh*0.16) { }
  if btn(cx, by0-bs,       bw, bh, A1R(), A1G(), A1B(), bw*0.38, bh*0.16) { }
  if btn(cx, by0-bs*2.0,   bw, bh, A2R(), A2G(), A2B(), bw*0.42, bh*0.16) { }
  if btn(cx, by0-bs*3.0,   bw, bh, A3R(), A3G(), A3B(), bw*0.38, bh*0.16) { }
  if btn(cx, by0-bs*4.0,   bw, bh, A2R(), A2G(), A2B(), bw*0.32, bh*0.16) { }
  if btn(cx, by0-bs*5.0,   bw, bh, A1R(), A1G(), A1B(), bw*0.36, bh*0.16) { }
}

// ── Right sidebar ──
fn draw_right() {
  let cx = 0.84; let cy = -0.01; let hw = 0.16; let hh = 0.86;
  pnl(cx, cy, hw, hh, hw*0.45, 0.012);

  let cp_y = cy+hh-0.09; let cp_s = 0.04;
  lbl(cx-hw+0.02, cp_y, hw*0.30, 0.010, TXR(), TXG(), TXB());
  rct(cx+0.015, cp_y-0.055, cp_s*0.9, cp_s*0.9, 0.12, 0.12, 0.18);
  rct(cx+0.015, cp_y-0.055, cp_s*0.8, cp_s*0.8, sr_r, sr_g, sr_b);

  let scy = cp_y-0.115;
  sr_r = sld(cx, scy, hw*0.55, 0.007, sr_r, 0.88, 0.15, 0.15, 10);
  lbl(cx-hw+0.02, scy, hw*0.08, 0.006, 0.88, 0.15, 0.15);
  sr_g = sld(cx, scy-0.035, hw*0.55, 0.007, sr_g, 0.15, 0.88, 0.15, 11);
  lbl(cx-hw+0.02, scy-0.035, hw*0.08, 0.006, 0.15, 0.88, 0.15);
  sr_b = sld(cx, scy-0.07, hw*0.55, 0.007, sr_b, 0.15, 0.15, 0.88, 12);
  lbl(cx-hw+0.02, scy-0.07, hw*0.08, 0.006, 0.15, 0.15, 0.88);
  sr_br = sld(cx, scy-0.12, hw*0.55, 0.007, sr_br, A2R(), A2G(), A2B(), 13);
  lbl(cx-hw+0.02, scy-0.12, hw*0.30, 0.006, A2R(), A2G(), A2B());

  let ab_y = cy-hh+0.07; let aw = hw*0.38; let ah = 0.028;
  if btn(cx, ab_y, aw, ah, A3R(), A3G(), A3B(), aw*0.14, ah*0.18) { }
  if btn(cx, ab_y-0.045, aw, ah, ADR(), ADG(), ADB(), aw*0.28, ah*0.18) { g_exit = 1; }
}

// ── Viewport ──
fn draw_vp() {
  let cx = 0.0; let cy = -0.01; let hw = 0.34; let hh = 0.86;
  pnl(cx, cy, hw, hh, hw*0.30, 0.012);
  vp_angle = vp_angle + 0.02; if vp_angle > 6.28 { vp_angle = 0.0; }
  draw_cube_3d_at(g_app, vp_angle, 0.0, -0.15, -2.0, 0.35);
  draw_cube_3d_at(g_app, vp_angle + 1.5, 0.35, -0.25, -2.5, 0.22);
  draw_cube_3d_at(g_app, vp_angle + 0.8, -0.3, -0.1, -1.8, 0.15);
}

// ── Status bar ──
fn draw_sb() {
  let cy = -0.96; let hh = 0.04;
  rct(0.0, cy, 1.0, hh, 0.10, 0.10, 0.14);
  rct(0.0, cy+hh-0.002, 1.0, 0.002, 0.22, 0.22, 0.26);
  rct(-0.96, cy, 0.008, 0.008, 0.12, 0.65, 0.25);
  lbl(-0.93, cy, 0.040, 0.008, TXR(), TXG(), TXB());
  lbl(0.35, cy, 0.022, 0.008, TMR(), TMG(), TMB());
  var bi = 0; var bx = 0.44;
  while bi < 8 {
    if bi < 4 { rct(bx, cy, 0.007, 0.009, 0.14, 0.68, 0.34); }
    else { rct(bx, cy, 0.007, 0.009, 0.08, 0.08, 0.12); }
    bx = bx + 0.013; bi = bi + 1;
  }
  lbl(0.55, cy, 0.025, 0.008, TMR(), TMG(), TMB());
}

// ── Main ──
fn main() -> Int {
  let app = create_app("XIOM Vulkan Showcase", 1280, 720);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_app = a;
      sr_r = 0.6; sr_g = 0.3; sr_b = 0.8; sr_br = 0.7;
      vp_angle = 0.0; sdr = 0;
      io.println("== XIOM Vulkan Showcase ==");
      io.println("Interactive: buttons, sliders, color picker, viewport.");
      io.println("Red Exit or Escape to close.");

      while !should_close(a) && g_exit == 0 {
        poll(a);

        let status = begin_frame(a);
        if status == 1 {
          set_clear_color(a, C0R(), C0G(), C0B());
          draw_top();
          draw_left();
          draw_right();
          draw_vp();
          draw_sb();
          end_frame(a);
          if is_key_down(a, 256) { io.println("[Showcase] Escape."); break; }
        } elif status == -1 {
          io.println("ERROR: " + last_error()); break;
        }
      }
      io.println("[Showcase] Done.");
      destroy_app(a);
      return 0;
    }
  }
}
