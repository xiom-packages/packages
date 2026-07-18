// G5 probe: var Vec literal + .data access → valid IR?
module probe_g5
extern "C" { fn xvk_take_floats(data: *UInt8, count: Int); }
fn main() -> Int {
  var v: Vec[Float32] = [1.0, 2.0, 3.0];
  let p = v.data;
  unsafe { xvk_take_floats(p, v.len()); }
  return 0;
}
