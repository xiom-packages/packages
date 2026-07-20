// XIOM — GLFW Bindings (Safe Windowing & Input)
// Standalone package. Zero Vulkan dependency.
// All functions return opaque Int handles (GLFWwindow* / GLFWmonitor*).

module xiom.glwf

extern "C" {
  fn glfw_bridge_init() -> Int32;
  fn glfw_bridge_terminate();
  fn glfw_bridge_create_window(w: Int32, h: Int32, title: Str) -> Int;
  fn glfw_bridge_destroy_window(window: Int);
  fn glfw_bridge_should_close(window: Int) -> Int32;
  fn glfw_bridge_set_window_title(window: Int, title: Str);
  fn glfw_bridge_get_framebuffer_size(window: Int, w: Int, h: Int);
  fn glfw_bridge_get_window_size(window: Int, w: Int, h: Int);
  fn glfw_bridge_poll_events();
  fn glfw_bridge_get_key(window: Int, key: Int32) -> Int32;
  fn glfw_bridge_get_mouse_button(window: Int, button: Int32) -> Int32;
  fn glfw_bridge_get_cursor_pos(window: Int, x: Int, y: Int);
  fn glfw_bridge_get_primary_monitor() -> Int;
  fn glfw_bridge_get_video_mode(monitor: Int, w: Int, h: Int, refresh: Int);
  fn glfw_bridge_set_window_monitor(window: Int, monitor: Int, x: Int32, y: Int32, w: Int32, h: Int32, refresh: Int32);
  fn glfw_bridge_get_window_monitor(window: Int) -> Int;
  fn glfw_bridge_get_error() -> Str;
}

// ── Lifecycle ──

pub fn init() -> Bool
{ return unsafe { glfw_bridge_init() != 0 }; }

pub fn terminate()
{ unsafe { glfw_bridge_terminate(); }; }

// ── Window ──

pub fn create_window(title: Str, w: Int, h: Int) -> Result[Int, Str]
  requires: title.len() > 0
  requires: w > 0
  requires: h > 0
{
  let win = unsafe { glfw_bridge_create_window(w as Int32, h as Int32, title) };
  if win == 0 { return Err(unsafe { glfw_bridge_get_error() }); };
  Ok(win)
}

pub fn destroy_window(win: Int)
  requires: win != 0
{ unsafe { glfw_bridge_destroy_window(win); }; }

pub fn should_close(win: Int) -> Bool
  requires: win != 0
{ return unsafe { glfw_bridge_should_close(win) != 0 }; }

pub fn set_title(win: Int, title: Str)
  requires: win != 0
{ unsafe { glfw_bridge_set_window_title(win, title); }; }

pub fn get_framebuffer_size(win: Int) -> (Int, Int)
  requires: win != 0
{
  var fw: Int32 = 0; var fh: Int32 = 0;
  unsafe { glfw_bridge_get_framebuffer_size(win, &fw, &fh); }
  return (fw as Int, fh as Int);
}

pub fn get_window_size(win: Int) -> (Int, Int)
  requires: win != 0
{
  var w: Int32 = 0; var h: Int32 = 0;
  unsafe { glfw_bridge_get_window_size(win, &w, &h); }
  return (w as Int, h as Int);
}

// ── Input ──

pub fn poll_events()
{ unsafe { glfw_bridge_poll_events(); }; }

pub fn get_key(win: Int, key: Int) -> Bool
  requires: win != 0
{ return unsafe { glfw_bridge_get_key(win, key as Int32) != 0 }; }

pub fn get_mouse_button(win: Int, button: Int) -> Bool
  requires: win != 0
{ return unsafe { glfw_bridge_get_mouse_button(win, button as Int32) != 0 }; }

pub fn get_cursor_pos(win: Int) -> (Float32, Float32)
  requires: win != 0
{
  var x: Float32 = 0.0; var y: Float32 = 0.0;
  unsafe { glfw_bridge_get_cursor_pos(win, &x, &y); }
  return (x, y);
}

// ── Monitors ──

pub fn get_primary_monitor() -> Int
{ return unsafe { glfw_bridge_get_primary_monitor() }; }

pub fn get_video_mode(monitor: Int) -> (Int, Int, Int)
  requires: monitor != 0
{
  var w: Int32 = 0; var h: Int32 = 0; var r: Int32 = 0;
  unsafe { glfw_bridge_get_video_mode(monitor, &w, &h, &r); }
  return (w as Int, h as Int, r as Int);
}

pub fn set_fullscreen(win: Int, monitor: Int, w: Int, h: Int, refresh: Int)
  requires: win != 0
{ unsafe { glfw_bridge_set_window_monitor(win, monitor, 0, 0, w as Int32, h as Int32, refresh as Int32); }; }

pub fn set_windowed(win: Int, x: Int, y: Int, w: Int, h: Int)
  requires: win != 0
{ unsafe { glfw_bridge_set_window_monitor(win, 0, x as Int32, y as Int32, w as Int32, h as Int32, 0); }; }

pub fn toggle_fullscreen(win: Int) -> Result[Unit, Str]
  requires: win != 0
{
  let cur = unsafe { glfw_bridge_get_window_monitor(win) };
  if cur != 0 {
    let mon = unsafe { glfw_bridge_get_primary_monitor() };
    var mw: Int32 = 0; var mh: Int32 = 0; var mr: Int32 = 0;
    unsafe { glfw_bridge_get_video_mode(mon, &mw, &mh, &mr); };
    unsafe { glfw_bridge_set_window_monitor(win, 0, 100, 100, (mw/2) as Int32, (mh/2) as Int32, 0); };
  } else {
    let mon = unsafe { glfw_bridge_get_primary_monitor() };
    var mw: Int32 = 0; var mh: Int32 = 0; var mr: Int32 = 0;
    unsafe { glfw_bridge_get_video_mode(mon, &mw, &mh, &mr); };
    unsafe { glfw_bridge_set_window_monitor(win, mon, 0, 0, mw, mh, mr); };
  }
  Ok(())
}
