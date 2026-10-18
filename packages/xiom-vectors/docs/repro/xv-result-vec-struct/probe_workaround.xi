// Controls + candidate workarounds for Result[Vec[non-scalar], E].
module probe_result_workaround

use xiom.io;

pub type SR = { id: Int; distance: Float32; }
pub type Hits = { items: Vec[SR]; }
pub enum CE { A, B, }

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

pub fn direct_vec_str() -> Vec[Str] {
  var v = Vec[Str].new(); v.push("alpha");
  return v;
}
pub fn r_hits_wrap() -> Result[Hits, CE] {
  var v = Vec[SR].new(); v.push(SR{ id: 42, distance: 1.5 });
  return Ok(Hits{ items: v });
}
pub fn o_vec_struct() -> Option[Vec[SR]] {
  var v = Vec[SR].new(); v.push(SR{ id: 42, distance: 1.5 });
  return Some(v);
}

fn main() -> Int {
  var d = direct_vec_str();
  io.println("direct_vec_str len=" + int_to_str(d.len()) + " v0=" + d[0]);
  match r_hits_wrap() {
    Ok(h) => { io.println("hits_wrap len=" + int_to_str(h.items.len()) + " id=" + int_to_str(h.items[0].id)); }
    Err(_) => { io.println("hits_wrap Err"); }
  }
  match o_vec_struct() {
    Some(v) => { io.println("option_vec_struct len=" + int_to_str(v.len()) + " id=" + int_to_str(v[0].id)); }
    None => { io.println("option_vec_struct None"); }
  }
  return 0;
}
