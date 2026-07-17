// probe5 — Vec.new + push path, then .data to C
module probe5

extern "C" {
  fn xvk_take_floats(data: Int, count: Int);
  fn xvk_probe_out(w: Int, h: Int);
}

fn main() -> Int {
  var v = Vec[Float32].new();
  v.push(1.5);
  v.push(2.5);
  v.push(3.5);
  unsafe { xvk_take_floats(v.data, v.len()); }

  var wh = Vec[Int32].new();
  wh.push(0);
  wh.push(0);
  unsafe { xvk_probe_out(wh.data, wh.data + 4); }
  let w: Int32 = wh[0];
  let h: Int32 = wh[1];
  if w == 800 && h == 600 { return 0; }
  return 7;
}
