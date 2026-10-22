module probe_tuple_main
use probe_vec_in_tuple_lib;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  match pair() {
    Ok((_h, v)) => { io.println("cross-module nominal len=" + convert.int_to_string(v.len())); }
    Err(_) => { io.println("err"); }
  }
  return 0;
}