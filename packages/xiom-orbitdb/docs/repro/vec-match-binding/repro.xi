// Minimal repro: a `let`/`var` initializer binding a Vec returned through a
// match from a Result gets a corrupted length in v0.64.8.
module repro.vec_match_binding

use xiom.io;

fn make3() -> Result[Vec[Int], Int] {
  var v = Vec[Int].new();
  v.push(10);
  v.push(20);
  v.push(30);
  return Ok(v);
}

fn via_let() -> Int {
  let v = match make3() {
    Ok(x) => { x }
    Err(_) => { return -1; }
  };
  return v.len();
}

fn via_var_init() -> Int {
  var v = match make3() {
    Ok(x) => { x }
    Err(_) => { return -1; }
  };
  return v.len();
}

fn via_var() -> Int {
  var v = Vec[Int].new();
  match make3() {
    Ok(x) => { v = x; }
    Err(_) => { return -1; }
  };
  return v.len();
}

fn direct_len() -> Int {
  match make3() {
    Ok(x) => { return x.len(); }
    Err(_) => { return -1; }
  }
}

pub fn main() -> Int {
  io.println("via_let=" + via_let().to_str());
  io.println("via_var_init=" + via_var_init().to_str());
  io.println("via_var=" + via_var().to_str());
  io.println("direct_len=" + direct_len().to_str());
  return 0;
}
