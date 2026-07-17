// probe14 — two separate Vec .data out-params, direct args
module probe14

extern "C" {
  fn xvk_probe_out(w: Int, h: Int);
}

fn main() -> Int {
  var wbuf = Vec[Int32].new();
  wbuf.push(0);
  var hbuf = Vec[Int32].new();
  hbuf.push(0);
  unsafe { xvk_probe_out(wbuf.data, hbuf.data); }
  let w: Int32 = wbuf[0];
  let h: Int32 = hbuf[0];
  if w != 800 { return 1; }
  if h != 600 { return 2; }
  return 0;
}
