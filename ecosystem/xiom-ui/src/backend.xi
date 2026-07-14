module xiom.ui.backend

use xiom.ui.types;
use xiom.ui.render;
use xiom.ui.theme;

extern "C" {
  fn xiom_alloc(size: UInt) -> *UInt8;
  fn xiom_free_ptr(ptr: *UInt8);
  fn xiom_read_byte(ptr: *UInt8, offset: Int) -> Int;
  fn xiom_write_byte(ptr: *UInt8, offset: Int, val: Int);
  fn xiom_str_to_cstr(s: Str) -> *UInt8;
  fn xiom_free_cstr(ptr: *UInt8);
}

extern "C" {
  fn glClear(mask: Int);
  fn glClearColor(r: Float32, g: Float32, b: Float32, a: Float32);
  fn glBegin(mode: Int);
  fn glEnd();
  fn glColor4f(r: Float32, g: Float32, b: Float32, a: Float32);
  fn glVertex2f(x: Float32, y: Float32);
  fn glRectf(x1: Float32, y1: Float32, x2: Float32, y2: Float32);
  fn glViewport(x: Int, y: Int, w: Int, h: Int);
  fn glMatrixMode(mode: Int);
  fn glLoadIdentity();
  fn glOrtho(left: Float64, right: Float64, bottom: Float64, top: Float64, near: Float64, far: Float64);
  fn glLineWidth(width: Float32);
  fn glEnable(cap: Int);
  fn glDisable(cap: Int);
  fn glScissor(x: Int, y: Int, w: Int, h: Int);
  fn glPushAttrib(mask: Int);
  fn glPopAttrib();
}

const GL_COLOR_BUFFER_BIT: Int = 16384;
const GL_DEPTH_BUFFER_BIT: Int = 256;
const GL_PROJECTION: Int = 5889;
const GL_MODELVIEW: Int = 5888;
const GL_TRIANGLES: Int = 4;
const GL_TRIANGLE_FAN: Int = 6;
const GL_LINE_LOOP: Int = 2;
const GL_LINES: Int = 1;
const GL_SCISSOR_TEST: Int = 3089;
const GL_ALL_ATTRIB_BITS: Int = 1048575;
const PI: Float32 = 3.14159265359;

fn draw_circle_segments(cx: Float32, cy: Float32, r: Float32, segments: Int) {
  var angle_step: Float32 = 2.0 * PI / segments;
  unsafe { glBegin(GL_TRIANGLE_FAN); };
  unsafe { glVertex2f(cx, cy); };
  var i: Int = 0;
  while i <= segments {
    var angle: Float32 = angle_step * i;
    var x = cx + r * cos_approx(angle);
    var y = cy + r * sin_approx(angle);
    unsafe { glVertex2f(x, y); };
    i = i + 1;
  };
  unsafe { glEnd(); };
}

fn cos_approx(x: Float32) -> Float32 {
  var x2 = x * x;
  return 1.0 - x2 / 2.0 + x2 * x2 / 24.0 - x2 * x2 * x2 / 720.0;
}

fn sin_approx(x: Float32) -> Float32 {
  var x3 = x * x * x;
  return x - x3 / 6.0 + x3 * x * x / 120.0 - x3 * x * x * x * x / 5040.0;
}

pub fn backend_setup_viewport(sw: Float32, sh: Float32) {
  unsafe { glViewport(0, 0, sw as Int, sh as Int); };
  unsafe { glMatrixMode(GL_PROJECTION); };
  unsafe { glLoadIdentity(); };
  unsafe { glOrtho(0.0, sw as Float64, sh as Float64, 0.0, -1.0, 1.0); };
  unsafe { glMatrixMode(GL_MODELVIEW); };
  unsafe { glLoadIdentity(); };
}

pub fn backend_clear_bg(bg: &Color) {
  unsafe { glClearColor(bg.r, bg.g, bg.b, bg.a); };
  unsafe { glClear(GL_COLOR_BUFFER_BIT); };
}

pub fn backend_render(render_list: &RenderList, theme: &Theme, screen_w: Float32, screen_h: Float32) {
  backend_setup_viewport(screen_w, screen_h);
  backend_clear_bg(&theme.bg_color);

  var i: Int = 0;
  var cmd_count = render_list.command_count();
  while i < cmd_count {
    match render_list.commands[i] {
      RectCmd(rect, color) => {
        unsafe { glColor4f(color.r, color.g, color.b, color.a); };
        unsafe { glRectf(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h); };
      },
      CircleCmd(center, radius, color) => {
        unsafe { glColor4f(color.r, color.g, color.b, color.a); };
        draw_circle_segments(center.x, center.y, radius, 32);
      },
      LineCmd(start, end, color, width) => {
        unsafe { glLineWidth(width); };
        unsafe { glColor4f(color.r, color.g, color.b, color.a); };
        unsafe { glBegin(GL_LINES); };
        unsafe { glVertex2f(start.x, start.y); };
        unsafe { glVertex2f(end.x, end.y); };
        unsafe { glEnd(); };
        unsafe { glLineWidth(1.0); };
      },
      TextCmd(_, _, _, _) => {},
      ImageCmd(_, _) => {},
      ClipCmd(rect) => {
        unsafe { glEnable(GL_SCISSOR_TEST); };
        var y_flipped = screen_h - rect.y - rect.h;
        unsafe { glScissor(rect.x as Int, y_flipped as Int, rect.w as Int, rect.h as Int); };
      },
      _ => {},
    };
    i = i + 1;
  };

  unsafe { glDisable(GL_SCISSOR_TEST); };
}

pub fn backend_render_single(cmd: &RenderCommand) {
  match cmd {
    RectCmd(rect, color) => {
      unsafe { glColor4f(color.r, color.g, color.b, color.a); };
      unsafe { glRectf(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h); };
    },
    CircleCmd(center, radius, color) => {
      unsafe { glColor4f(color.r, color.g, color.b, color.a); };
      draw_circle_segments(center.x, center.y, radius, 32);
    },
    LineCmd(start, end, color, width) => {
      unsafe { glLineWidth(width); };
      unsafe { glColor4f(color.r, color.g, color.b, color.a); };
      unsafe { glBegin(GL_LINES); };
      unsafe { glVertex2f(start.x, start.y); };
      unsafe { glVertex2f(end.x, end.y); };
      unsafe { glEnd(); };
      unsafe { glLineWidth(1.0); };
    },
    _ => {},
  };
}
