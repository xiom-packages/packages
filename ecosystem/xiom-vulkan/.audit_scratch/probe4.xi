// probe4 — Vec element layout for FFI + readback
module probe4

extern "C" {
  fn xvk_take_floats(data: Int, count: Int);
}

fn main() -> Int {
  var v: Vec[Float32] = [1.5, 2.5, 3.5];
  unsafe { xvk_take_floats(v.data, v.len()); }
  var wh: Vec[Int32] = [0, 0];
  unsafe { xvk_take_floats(wh.data, wh.len()); }
  let a: Int32 = wh[0];
  return a as Int;
}
