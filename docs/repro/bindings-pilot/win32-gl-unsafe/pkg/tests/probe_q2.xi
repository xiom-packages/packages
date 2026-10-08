module opengl_probe_q2

use xiom.io;
use opengl_q2;

fn main() -> Int {
  io.println("q2-start");
  io.flush_stdout();
  let l = q2_load();
  if !l.is_ok {
    io.println("load failed: " + l.error);
    io.flush_stdout();
    return 1;
  }
  let lib: Q2Lib = l.value;
  let v = q2_query(&lib);
  io.println("gl_version_len=" + "0");
  io.println(v);
  io.flush_stdout();
  return 0;
}
