module glfw_probe18

use xiom.io;
use xiom.convert;
use xiom.glfw;

fn main() -> Int {
  let l = glfw_load();
  let lib: GlfwLibrary = l.value;
  if !glfw_init(&lib) { io.println("t0: no init"); return 1; }
  glfw_default_window_hints(&lib);
  glfw_window_hint(&lib, GLFW_VISIBLE, GLFW_FALSE);
  glfw_window_hint(&lib, GLFW_CLIENT_API, GLFW_NO_API);
  let cw = glfw_create_window(&lib, 200, 100, "probe18", 0, 0);
  if !cw.is_ok { io.println("t1: create err"); return 1; }
  let w: GlfwWindow = cw.value;
  let op = glfw_get_window_opacity(&lib, &w);
  io.println("opacity_x1000=" + to_string((op * 1000.0) as Int));
  io.flush_stdout();
  let vs = glfw_get_version_string(&lib);
  io.println("vs_len=" + to_string(vs.len()));
  io.flush_stdout();
  let t = glfw_get_time(&lib);
  io.println("gettime_ms=" + to_string((t * 1000.0) as Int));
  io.flush_stdout();
  return 0;
}
