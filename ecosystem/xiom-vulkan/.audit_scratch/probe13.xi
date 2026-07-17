// probe13 — .data pointer arithmetic for two-out-param calls
module probe13

extern "C" {
  fn xvk_probe_out(w: Int, h: Int);
}

fn main() -> Int {
  var wh = Vec[Int32].new();
  wh.push(0);
  wh.push(0);
  let base = wh.data;
  unsafe { xvk_probe_out(base, base + 4); }
  let w: Int32 = wh[0];
  let h: Int32 = wh[1];
  if w != 800 { return 1; }
  if h != 600 { return 2; }
  return 0;
}
