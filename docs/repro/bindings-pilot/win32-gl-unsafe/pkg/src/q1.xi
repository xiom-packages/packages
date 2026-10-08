module opengl_q1

use xiom.ffi.dl;

pub type Q1Lib = {
  h_user32: Int;
  h_gdi32: Int;
  p_create_window: Int;
  p_destroy_window: Int;
  p_get_dc: Int;
  p_release_dc: Int;
}

pub fn q1_load() -> Result[Q1Lib, Str] {
  let hu = dl.dl_open("user32.dll");
  if !hu.is_ok { return Err(hu.error); }
  let u: Int = hu.value;
  let b1 = dl.dl_sym(u, "CreateWindowExA");
  if !b1.is_ok { var ig = dl.dl_close(u); return Err(b1.error); }
  let b2 = dl.dl_sym(u, "DestroyWindow");
  if !b2.is_ok { var ig = dl.dl_close(u); return Err(b2.error); }
  let b3 = dl.dl_sym(u, "GetDC");
  if !b3.is_ok { var ig = dl.dl_close(u); return Err(b3.error); }
  let b4 = dl.dl_sym(u, "ReleaseDC");
  if !b4.is_ok { var ig = dl.dl_close(u); return Err(b4.error); }
  let hg = dl.dl_open("gdi32.dll");
  if !hg.is_ok { var ig = dl.dl_close(u); return Err(hg.error); }
  let g: Int = hg.value;
  return Ok(Q1Lib{
    h_user32: u,
    h_gdi32: g,
    p_create_window: b1.value,
    p_destroy_window: b2.value,
    p_get_dc: b3.value,
    p_release_dc: b4.value,
  });
}

pub fn q1_window_roundtrip(lib: &Q1Lib) -> Int
  requires: lib.h_user32 != 0
{
  unsafe {
    let create_window = lib.p_create_window as fn(Int, *UInt8, *UInt8, Int, Int, Int, Int, Int, Int, Int, Int, Int) -> Int;
    let hwnd = create_window(0, "STATIC".c_str(), "xiom-opengl-probe".c_str(), 0, 0, 0, 1, 1, 0, 0, 0, 0);
    if hwnd == 0 { return 1; }
    let get_dc = lib.p_get_dc as fn(Int) -> Int;
    let hdc = get_dc(hwnd);
    if hdc == 0 {
      let destroy_window = lib.p_destroy_window as fn(Int) -> Int32;
      var ig = destroy_window(hwnd);
      return 2;
    }
    let release_dc = lib.p_release_dc as fn(Int, Int) -> Int32;
    var ig1 = release_dc(hwnd, hdc);
    let destroy_window = lib.p_destroy_window as fn(Int) -> Int32;
    var ig2 = destroy_window(hwnd);
    return 0;
  }
}

pub fn q1_close(lib: &Q1Lib) -> Result[Unit, Str]
  requires: lib.h_user32 != 0
{
  let a = dl.dl_close(lib.h_gdi32);
  let b = dl.dl_close(lib.h_user32);
  if !a.is_ok { return Err(a.error); }
  if !b.is_ok { return Err(b.error); }
  return Ok({});
}
