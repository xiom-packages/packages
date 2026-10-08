module opengl_q2

use xiom.ffi.dl;

pub type Q2Lib = {
  h_gl: Int;
  h_user32: Int;
  h_gdi32: Int;
  p_get_string: Int;
  p_create_context: Int;
  p_make_current: Int;
  p_delete_context: Int;
  p_create_window: Int;
  p_destroy_window: Int;
  p_get_dc: Int;
  p_release_dc: Int;
  p_choose_format: Int;
  p_set_format: Int;
}

fn w8(buf: &mut Vec[UInt8], idx: Int, v: Int)
  requires: idx >= 0
  requires: idx < buf.len()
  requires: v >= 0
  requires: v <= 255
{
  buf[idx] = v as UInt8;
}

fn w16(buf: &mut Vec[UInt8], idx: Int, v: Int)
  requires: idx >= 0
  requires: idx + 1 < buf.len()
  requires: v >= 0
  requires: v <= 65535
{
  buf[idx] = (v & 0xFF) as UInt8;
  buf[idx + 1] = ((v >> 8) & 0xFF) as UInt8;
}

fn w32(buf: &mut Vec[UInt8], idx: Int, v: Int)
  requires: idx >= 0
  requires: idx + 3 < buf.len()
{
  buf[idx] = (v & 0xFF) as UInt8;
  buf[idx + 1] = ((v >> 8) & 0xFF) as UInt8;
  buf[idx + 2] = ((v >> 16) & 0xFF) as UInt8;
  buf[idx + 3] = ((v >> 24) & 0xFF) as UInt8;
}

fn pfd() -> Vec[UInt8]
  requires: true
{
  var p: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 40 {
    p.push(0 as UInt8);
    i = i + 1;
  }
  w16(&mut p, 0, 40);
  w16(&mut p, 2, 1);
  w32(&mut p, 4, 0x25);
  w8(&mut p, 8, 0);
  w8(&mut p, 9, 32);
  w8(&mut p, 23, 24);
  w8(&mut p, 24, 8);
  w8(&mut p, 26, 0);
  return p;
}

pub fn q2_load() -> Result[Q2Lib, Str] {
  let hgl = dl.dl_open("opengl32.dll");
  if !hgl.is_ok { return Err(hgl.error); }
  let gl: Int = hgl.value;
  let a1 = dl.dl_sym(gl, "glGetString");
  if !a1.is_ok { var ig = dl.dl_close(gl); return Err(a1.error); }
  let a3 = dl.dl_sym(gl, "wglCreateContext");
  if !a3.is_ok { var ig = dl.dl_close(gl); return Err(a3.error); }
  let a4 = dl.dl_sym(gl, "wglMakeCurrent");
  if !a4.is_ok { var ig = dl.dl_close(gl); return Err(a4.error); }
  let a5 = dl.dl_sym(gl, "wglDeleteContext");
  if !a5.is_ok { var ig = dl.dl_close(gl); return Err(a5.error); }
  let hu = dl.dl_open("user32.dll");
  if !hu.is_ok { var ig = dl.dl_close(gl); return Err(hu.error); }
  let u: Int = hu.value;
  let b1 = dl.dl_sym(u, "CreateWindowExA");
  if !b1.is_ok { var ig1 = dl.dl_close(u); var ig2 = dl.dl_close(gl); return Err(b1.error); }
  let b2 = dl.dl_sym(u, "DestroyWindow");
  if !b2.is_ok { var ig1 = dl.dl_close(u); var ig2 = dl.dl_close(gl); return Err(b2.error); }
  let b3 = dl.dl_sym(u, "GetDC");
  if !b3.is_ok { var ig1 = dl.dl_close(u); var ig2 = dl.dl_close(gl); return Err(b3.error); }
  let b4 = dl.dl_sym(u, "ReleaseDC");
  if !b4.is_ok { var ig1 = dl.dl_close(u); var ig2 = dl.dl_close(gl); return Err(b4.error); }
  let hg = dl.dl_open("gdi32.dll");
  if !hg.is_ok { var ig1 = dl.dl_close(u); var ig2 = dl.dl_close(gl); return Err(hg.error); }
  let g: Int = hg.value;
  let c1 = dl.dl_sym(g, "ChoosePixelFormat");
  if !c1.is_ok { var ig1 = dl.dl_close(g); var ig2 = dl.dl_close(u); var ig3 = dl.dl_close(gl); return Err(c1.error); }
  let c2 = dl.dl_sym(g, "SetPixelFormat");
  if !c2.is_ok { var ig1 = dl.dl_close(g); var ig2 = dl.dl_close(u); var ig3 = dl.dl_close(gl); return Err(c2.error); }
  return Ok(Q2Lib{
    h_gl: gl,
    h_user32: u,
    h_gdi32: g,
    p_get_string: a1.value,
    p_create_context: a3.value,
    p_make_current: a4.value,
    p_delete_context: a5.value,
    p_create_window: b1.value,
    p_destroy_window: b2.value,
    p_get_dc: b3.value,
    p_release_dc: b4.value,
    p_choose_format: c1.value,
    p_set_format: c2.value,
  });
}

pub fn q2_query(lib: &Q2Lib) -> Str
  requires: lib.h_gl != 0
{
  unsafe {
    let create_window = lib.p_create_window as fn(Int, *UInt8, *UInt8, Int, Int, Int, Int, Int, Int, Int, Int, Int) -> Int;
    let hwnd = create_window(0, "STATIC".c_str(), "xiom-opengl-q2".c_str(), 0, 0, 0, 1, 1, 0, 0, 0, 0);
    if hwnd == 0 { return ""; }
    let get_dc = lib.p_get_dc as fn(Int) -> Int;
    let hdc = get_dc(hwnd);
    if hdc == 0 {
      let destroy_window = lib.p_destroy_window as fn(Int) -> Int32;
      var ig = destroy_window(hwnd);
      return "";
    }
    var pf = pfd();
    let choose_format = lib.p_choose_format as fn(Int, *UInt8) -> Int32;
    let fmt = choose_format(hdc, pf.as_mut_ptr());
    if fmt == 0 {
      let release_dc = lib.p_release_dc as fn(Int, Int) -> Int32;
      var ig1 = release_dc(hwnd, hdc);
      let destroy_window = lib.p_destroy_window as fn(Int) -> Int32;
      var ig2 = destroy_window(hwnd);
      return "";
    }
    let set_format = lib.p_set_format as fn(Int, Int32, *UInt8) -> Int32;
    let set_ok = set_format(hdc, fmt, pf.as_mut_ptr());
    if set_ok == 0 {
      let release_dc = lib.p_release_dc as fn(Int, Int) -> Int32;
      var ig1 = release_dc(hwnd, hdc);
      let destroy_window = lib.p_destroy_window as fn(Int) -> Int32;
      var ig2 = destroy_window(hwnd);
      return "";
    }
    let create_context = lib.p_create_context as fn(Int) -> Int;
    let hglrc = create_context(hdc);
    if hglrc == 0 {
      let release_dc = lib.p_release_dc as fn(Int, Int) -> Int32;
      var ig1 = release_dc(hwnd, hdc);
      let destroy_window = lib.p_destroy_window as fn(Int) -> Int32;
      var ig2 = destroy_window(hwnd);
      return "";
    }
    let make_current = lib.p_make_current as fn(Int, Int) -> Int32;
    let cur = make_current(hdc, hglrc);
    if cur == 0 {
      let delete_context = lib.p_delete_context as fn(Int) -> Int32;
      var ig1 = delete_context(hglrc);
      let release_dc = lib.p_release_dc as fn(Int, Int) -> Int32;
      var ig2 = release_dc(hwnd, hdc);
      let destroy_window = lib.p_destroy_window as fn(Int) -> Int32;
      var ig3 = destroy_window(hwnd);
      return "";
    }
    let f = lib.p_get_string as fn(Int) -> *UInt8;
    var version = "";
    let pv = f(0x1F02);
    if (pv as Int) != 0 { version = Str::from_c_str(pv); }
    var ig0 = make_current(0, 0);
    let delete_context = lib.p_delete_context as fn(Int) -> Int32;
    var ig1 = delete_context(hglrc);
    let release_dc = lib.p_release_dc as fn(Int, Int) -> Int32;
    var ig2 = release_dc(hwnd, hdc);
    let destroy_window = lib.p_destroy_window as fn(Int) -> Int32;
    var ig3 = destroy_window(hwnd);
    return version;
  }
}
