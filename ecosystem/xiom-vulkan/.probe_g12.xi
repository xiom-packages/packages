// G12-e2e: Vec→Ptr cast + &local out-param produce correct LLVM IR
module probe_g12_e2e
extern "C" {
  fn xvk_take_floats(data: *UInt8, count: Int);
  fn xvk_fill_wh(w: *Int32, h: *Int32);
}
fn main() -> Int {
  // G1: Vec→Ptr cast for buffer data upload
  var v: Vec[Float32] = [1.5, 2.5, 3.5];
  unsafe { xvk_take_floats(v as *UInt8, v.len()); }
  // G2: &local passed as out-param pointer
  var w: Int32 = 0;
  var h: Int32 = 0;
  unsafe { xvk_fill_wh(&w, &h); }
  if w != 800 { return 1; }
  if h != 600 { return 2; }
  return 0;
}
