module glfw_probe16

use xiom.io;
use xiom.convert;
use xiom.glfw;

fn main() -> Int {
  let l = glfw_load();
  let lib: GlfwLibrary = l.value;
  if !glfw_init(&lib) { io.println("t0: no init"); return 1; }
  let ta = glfw_get_time(&lib);
  glfw_wait_events_timeout(&lib, 0.30);
  let tb = glfw_get_time(&lib);
  io.println("advance_ms=" + to_string(((tb - ta) * 1000.0) as Int));
  io.flush_stdout();
  glfw_set_time(&lib, 99.0);
  let tc = glfw_get_time(&lib);
  io.println("after_set99_ms=" + to_string((tc * 1000.0) as Int));
  io.flush_stdout();
  return 0;
}
