// Matrix: which Result[T, E] payload shapes survive a return?
module probe_result_matrix

use xiom.io;

pub type SR = { id: Int; distance: Float32; }
pub enum CE { A, B, }
pub enum SE { A, B, Bad(msg: Str), }

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = ""; var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  if neg { out = "-" + out; }
  return out;
}

pub fn r_struct() -> Result[SR, CE] {
  return Ok(SR{ id: 42, distance: 1.5 });
}
pub fn r_vec_int() -> Result[Vec[Int], CE] {
  var v = Vec[Int].new(); v.push(7); v.push(8);
  return Ok(v);
}
pub fn r_vec_str() -> Result[Vec[Str], CE] {
  var v = Vec[Str].new(); v.push("alpha");
  return Ok(v);
}
pub fn r_vec_struct_unit_err() -> Result[Vec[SR], CE] {
  var v = Vec[SR].new(); v.push(SR{ id: 42, distance: 1.5 });
  return Ok(v);
}
pub fn r_vec_struct_str_err() -> Result[Vec[SR], SE] {
  var v = Vec[SR].new(); v.push(SR{ id: 42, distance: 1.5 });
  return Ok(v);
}
pub fn r_scalar_int() -> Result[Int, CE] {
  return Ok(99);
}

fn main() -> Int {
  match r_scalar_int() {
    Ok(x) => { io.println("scalar_int Ok=" + int_to_str(x)); }
    Err(_) => { io.println("scalar_int Err"); }
  }
  match r_struct() {
    Ok(s) => { io.println("struct id=" + int_to_str(s.id)); }
    Err(_) => { io.println("struct Err"); }
  }
  match r_vec_int() {
    Ok(v) => { io.println("vec_int len=" + int_to_str(v.len()) + " v0=" + int_to_str(v[0]) + " v1=" + int_to_str(v[1])); }
    Err(_) => { io.println("vec_int Err"); }
  }
  match r_vec_str() {
    Ok(v) => { io.println("vec_str len=" + int_to_str(v.len()) + " v0=" + v[0]); }
    Err(_) => { io.println("vec_str Err"); }
  }
  match r_vec_struct_unit_err() {
    Ok(v) => { io.println("vec_struct_unit_err len=" + int_to_str(v.len()) + " id=" + int_to_str(v[0].id)); }
    Err(_) => { io.println("vec_struct_unit_err Err"); }
  }
  match r_vec_struct_str_err() {
    Ok(v) => { io.println("vec_struct_str_err len=" + int_to_str(v.len()) + " id=" + int_to_str(v[0].id)); }
    Err(_) => { io.println("vec_struct_str_err Err"); }
  }
  return 0;
}
