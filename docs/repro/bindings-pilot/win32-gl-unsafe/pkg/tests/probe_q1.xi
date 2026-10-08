module opengl_probe_q1

use xiom.io;
use xiom.convert;
use opengl_q1;

fn main() -> Int {
  io.println("q1-start");
  io.flush_stdout();
  let l = q1_load();
  if !l.is_ok {
    io.println("load failed: " + l.error);
    io.flush_stdout();
    return 1;
  }
  let lib: Q1Lib = l.value;
  let rc = q1_window_roundtrip(&lib);
  io.println("roundtrip_rc=" + to_string(rc));
  io.flush_stdout();
  let cl = q1_close(&lib);
  io.println("close=" + to_string(0));
  io.flush_stdout();
  return 0;
}
