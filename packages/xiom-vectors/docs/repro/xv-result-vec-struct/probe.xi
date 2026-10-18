// Minimal repro: Result[Vec[Struct], Enum] returned from a function -- does
// the Ok payload preserve element fields?
module probe_result_vec_struct

use xiom.io;

pub type SR = { id: Int; distance: Float32; }

pub enum CE {
  NotFound,
  InvalidInput(msg: Str),
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = "";
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  return out;
}

pub fn make_vec() -> Vec[SR] {
  var v = Vec[SR].new();
  var s = SR{ id: 42, distance: 1.5 };
  v.push(s);
  return v;
}

pub fn make_result() -> Result[Vec[SR], CE] {
  var v = Vec[SR].new();
  var s = SR{ id: 42, distance: 1.5 };
  v.push(s);
  return Ok(v);
}

pub fn make_result_inline() -> Result[Vec[SR], CE] {
  return Ok(make_vec());
}

fn main() -> Int {
  var a = make_vec();
  io.println("direct len=" + int_to_str(a.len()) + " id=" + int_to_str(a[0].id));
  match make_result() {
    Ok(v) => { io.println("wrapped len=" + int_to_str(v.len()) + " id=" + int_to_str(v[0].id)); }
    Err(_) => { io.println("wrapped Err"); }
  }
  match make_result_inline() {
    Ok(v) => { io.println("inline len=" + int_to_str(v.len()) + " id=" + int_to_str(v[0].id)); }
    Err(_) => { io.println("inline Err"); }
  }
  return 0;
}
