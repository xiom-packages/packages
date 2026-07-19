// XIOM Vulkan Showcase — Production Demo
// Game-style GUI with REAL text rendering via font atlas + textured quads.
// Buttons: hover/press/normal states. Sliders: draggable. Exit button.

module demo_vulkan
use xiom.io;
use xiom.vulkan;

// ── Global state ──
var g_app: Int = 0;
var g_exit: Int = 0;
var g_font: Int = 0;
var g_fsize: Float32 = 24.0;

// ── Quick draw ──
fn rct(cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32) {
  draw_quad_2d(g_app, cx, cy, hw, hh, r, g, b);
}
fn ht(cx: Float32, cy: Float32, hw: Float32, hh: Float32) -> Int {
  return unsafe { xvk_button_hit_state(g_app, cx, cy, hw, hh) } as Int;
}
fn md() -> Bool { return is_mouse_down(g_app, 0); }

// ── Text rendering — font → pixels → GPU texture → textured quad ──
fn make_text_tex(msg: Str) -> Int {
  let wb = unsafe { xvk_alloc(4) }; let hb = unsafe { xvk_alloc(4) };
  let px = unsafe { xvk_font_render_text(g_font, msg, wb, hb) };
  if px == 0 { unsafe { xvk_free(wb); xvk_free(hb); }; return 0; }
  let w = unsafe { xvk_read_u32(wb, 0) } as Int; let h = unsafe { xvk_read_u32(hb, 0) } as Int;
  unsafe { xvk_free(wb); xvk_free(hb); };
  if w <= 0 || h <= 0 { unsafe { xvk_font_free_pixels(px); }; return 0; }
  let tex = texture_create(g_app, px, w, h, 0);
  unsafe { xvk_font_free_pixels(px); }
  return tex;
}

// Cached label textures (created once at startup, reused each frame)
var g_tx_title: Int = 0;
var g_tx_t1: Int = 0; var g_tx_t2: Int = 0; var g_tx_t3: Int = 0;
var g_tx_t4: Int = 0; var g_tx_t5: Int = 0; var g_tx_t6: Int = 0;
var g_tx_exit: Int = 0;
var g_tx_color: Int = 0; var g_tx_ok: Int = 0;
var g_tx_cancel: Int = 0; var g_tx_apply: Int = 0;

fn init_textures() {
  g_font = font_create(g_fsize);
  g_tx_title = make_text_tex("XIOM Vulkan Showcase v0.3.3");
  g_tx_t1 = make_text_tex("Triangle");
  g_tx_t2 = make_text_tex("Cubes");
  g_tx_t3 = make_text_tex("Particles");
  g_tx_t4 = make_text_tex("Sprites");
  g_tx_t5 = make_text_tex("Mesh");
  g_tx_t6 = make_text_tex("Compute");
  g_tx_exit = make_text_tex("Exit");
  g_tx_color = make_text_tex("Color");
  g_tx_ok = make_text_tex("OK");
  g_tx_cancel = make_text_tex("Cancel");
  g_tx_apply = make_text_tex("Apply");
}

fn draw_tex(tex: Int, cx: Float32, cy: Float32, hw: Float32, hh: Float32) {
  if tex == 0 { return; }
  let view = texture_get_image_view(tex);
  let samp = texture_get_sampler(tex);
  if view != 0 {
    draw_texture_quad(g_app, view, samp, cx, cy, hw, hh);
  }
}

fn tex_w(tex: Int) -> Float32 {
  if tex == 0 { return 0.02; }
  let w = texture_get_width(tex); let h = texture_get_height(tex);
  if h <= 0 { return 0.02; }
  let aspect = (w as Float32) / (h as Float32);
  return 0.018 * aspect;
}
fn tex_h() -> Float32 { return 0.018; }

// ── Button: 3 states ──
fn btn(cx: Float32, cy: Float32, hw: Float32, hh: Float32,
       ar: Float32, ag: Float32, ab: Float32, tx: Int) -> Bool {
  let s = ht(cx, cy, hw, hh);
  var br = 0.12; var bg = 0.14; var bb = 0.18;
  if s == 1 { br = 0.22; bg = 0.26; bb = 0.32; }
  if s == 2 { br = 0.07; bg = 0.08; bb = 0.11; }
  rct(cx, cy, hw, hh, br, bg, bb);
  rct(cx, cy+hh-0.001, hw*0.96, 0.0015, br+0.08, bg+0.08, bb+0.10);
  rct(cx, cy-hh+0.001, hw*0.96, 0.0015, br-0.04, bg-0.04, bb-0.05);
  let sh = hh*0.12; if sh < 0.002 { sh = 0.002; }
  rct(cx, cy-hh+sh+0.001, hw*0.88, sh, ar, ag, ab);
  if tx != 0 { draw_tex(tx, cx + hw*0.06, cy + hh*0.08, tex_w(tx), tex_h()); }
  return s == 1 && !md();
}

// ── Panel ──
fn pnl(cx: Float32, cy: Float32, hw: Float32, hh: Float32, tx: Int) {
  rct(cx, cy, hw, hh, 0.07, 0.08, 0.11);
  let bw = 0.003;
  rct(cx-hw+bw, cy, bw, hh*0.96, 0.14, 0.44, 0.60);
  rct(cx+hw-bw, cy, bw, hh*0.96, 0.14, 0.44, 0.60);
  rct(cx, cy+hh-bw, hw*0.96, bw, 0.14, 0.44, 0.60);
  rct(cx, cy-hh+bw, hw*0.96, bw, 0.14, 0.44, 0.60);
  rct(cx, cy+hh-0.012, hw*0.92, 0.025, 0.10, 0.40, 0.56);
  if tx != 0 { draw_tex(tx, cx-hw+0.04, cy+hh-0.012, tex_w(tx), tex_h()); }
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
  let fv = v*fw;
  if fv > 0.003 { rct(cx-fw+fv, cy, fv, fh, tr*0.6, tg*0.6, tb*0.6); }
  let tx = cx-hw+v*hw*2.0;
  rct(tx, cy, hh*2.2, hh*3.2, tr, tg, tb);
  return v;
}

// Slider state
var sr_r: Float32 = 0.0; var sr_g: Float32 = 0.0; var sr_b: Float32 = 0.0;
var sr_br: Float32 = 0.0;
var vp_angle: Float32 = 0.0;

// ── Top bar ──
fn draw_top() {
  let cy = 0.94; let hh = 0.06;
  rct(0.0, cy, 1.0, hh, 0.10, 0.10, 0.14);
  rct(0.0, cy+hh-0.002, 1.0, 0.002, 0.22, 0.22, 0.26);
  rct(0.0, cy-hh+0.004, 1.0, 0.004, 0.04, 0.04, 0.07);
  draw_tex(g_tx_title, -0.15, cy, tex_w(g_tx_title), tex_h());
  var bx = -0.88; var bw = 0.07; var bh = hh*0.65; var gap = 0.08;
  if btn(bx, cy, bw, bh, 0.16,0.64,0.88, g_tx_t1) { }
  if btn(bx+gap, cy, bw, bh, 0.88,0.55,0.16, g_tx_t2) { }
  if btn(bx+gap*2.0, cy, bw, bh, 0.16,0.88,0.55, g_tx_t3) { }
  if btn(bx+gap*3.0, cy, bw, bh, 0.88,0.20,0.32, g_tx_exit) { g_exit = 1; }
}

// ── Left sidebar ──
fn draw_left() {
  let cx = -0.84; let cy = -0.01; let hw = 0.16; let hh = 0.86;
  pnl(cx, cy, hw, hh, g_tx_t1);
  var bw = hw*0.75; var bh = 0.032; var by0 = cy+hh-0.10; var bs = 0.054;
  if btn(cx, by0,          bw, bh, 0.16,0.64,0.88, g_tx_t1) { }
  if btn(cx, by0-bs,       bw, bh, 0.16,0.64,0.88, g_tx_t2) { }
  if btn(cx, by0-bs*2.0,   bw, bh, 0.88,0.55,0.16, g_tx_t3) { }
  if btn(cx, by0-bs*3.0,   bw, bh, 0.16,0.88,0.55, g_tx_t4) { }
  if btn(cx, by0-bs*4.0,   bw, bh, 0.88,0.55,0.16, g_tx_t5) { }
  if btn(cx, by0-bs*5.0,   bw, bh, 0.16,0.64,0.88, g_tx_t6) { }
}

// ── Right sidebar ──
fn draw_right() {
  let cx = 0.84; let cy = -0.01; let hw = 0.16; let hh = 0.86;
  pnl(cx, cy, hw, hh, g_tx_color);
  let cp_y = cy+hh-0.09; let cp_s = 0.04;
  draw_tex(g_tx_color, cx-hw+0.02, cp_y, tex_w(g_tx_color), tex_h());
  rct(cx+0.015, cp_y-0.055, cp_s*0.9, cp_s*0.9, 0.12, 0.12, 0.18);
  rct(cx+0.015, cp_y-0.055, cp_s*0.8, cp_s*0.8, sr_r, sr_g, sr_b);

  let scy = cp_y-0.115;
  sr_r = sld(cx, scy, hw*0.55, 0.007, sr_r, 0.88,0.15,0.15, 10);
  rct(cx-hw+0.02, scy, hw*0.08, 0.006, 0.88, 0.15, 0.15);
  sr_g = sld(cx, scy-0.035, hw*0.55, 0.007, sr_g, 0.15,0.88,0.15, 11);
  rct(cx-hw+0.02, scy-0.035, hw*0.08, 0.006, 0.15, 0.88, 0.15);
  sr_b = sld(cx, scy-0.07, hw*0.55, 0.007, sr_b, 0.15,0.15,0.88, 12);
  rct(cx-hw+0.02, scy-0.07, hw*0.08, 0.006, 0.15, 0.15, 0.88);
  sr_br = sld(cx, scy-0.12, hw*0.55, 0.007, sr_br, 0.88,0.55,0.16, 13);
  rct(cx-hw+0.02, scy-0.12, hw*0.30, 0.006, 0.88, 0.55, 0.16);

  let ab_y = cy-hh+0.07; let aw = hw*0.38; let ah = 0.028;
  if btn(cx, ab_y, aw, ah, 0.16,0.88,0.55, g_tx_ok) { }
  if btn(cx, ab_y-0.045, aw, ah, 0.88,0.20,0.32, g_tx_exit) { g_exit = 1; }
}

// ── Viewport ──
fn draw_vp() {
  let cx = 0.0; let cy = -0.01; let hw = 0.34; let hh = 0.86;
  pnl(cx, cy, hw, hh, g_tx_title);
  vp_angle = vp_angle + 0.02; if vp_angle > 6.28 { vp_angle = 0.0; }
  draw_cube_3d_at(g_app, vp_angle, 0.0, -0.15, -2.0, 0.35);
  draw_cube_3d_at(g_app, vp_angle + 1.5, 0.35, -0.25, -2.5, 0.22);
}

// ── Status bar ──
fn draw_sb() {
  let cy = -0.96; let hh = 0.04;
  rct(0.0, cy, 1.0, hh, 0.10, 0.10, 0.14);
  rct(0.0, cy+hh-0.002, 1.0, 0.002, 0.22, 0.22, 0.26);
  rct(-0.96, cy, 0.008, 0.008, 0.12, 0.65, 0.25);
  draw_tex(g_tx_ok, -0.92, cy, tex_w(g_tx_ok), tex_h());
}

// ── Main ──
fn main() -> Int {
  let app = create_app("XIOM Vulkan Showcase v0.3.3", 1280, 720);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_app = a;
      sr_r = 0.6; sr_g = 0.3; sr_b = 0.8; sr_br = 0.7; vp_angle = 0.0;
      init_textures();
      io.println("== XIOM Vulkan Showcase v0.3.3 ==");
      io.println("Real text rendering via font atlas + textured quads.");
      io.println("Interactive buttons, sliders, exit button.");

      while !should_close(a) && g_exit == 0 {
        poll(a);
        let status = begin_frame(a);
        if status == 1 {
          set_clear_color(a, 0.04, 0.04, 0.06);
          draw_top(); draw_left(); draw_right(); draw_vp(); draw_sb();
          end_frame(a);
          if is_key_down(a, 256) { io.println("[Showcase] Escape."); break; }
        } elif status == -1 {
          io.println("ERROR: " + last_error()); break;
        }
      }
      destroy_app(a);
      return 0;
    }
  }
}
