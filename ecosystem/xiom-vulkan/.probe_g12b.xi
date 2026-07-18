// G12b: push-built Vec + as cast — does this path work?
module probe_g12b
extern "C" {
  fn xvk_take_floats(data: *UInt8, count: Int);
  fn xvk_fill_wh(w: *Int32, h: *Int32);
}
fn main() -> Int {
  // G1: push-built Vec + as *UInt8
  var v = Vec[Float32].new();
  v.push(1.5); v.push(2.5); v.push(3.5);
  unsafe { xvk_take_floats(v as *UInt8, v.len()); }
  // G2: &local out-param
  var w: Int32 = 0;
  var h: Int32 = 0;
  unsafe { xvk_fill_wh(&w, &h); }
  if w != 800 { return 1; }
  if h != 600 { return 2; }
  return 0;
}
