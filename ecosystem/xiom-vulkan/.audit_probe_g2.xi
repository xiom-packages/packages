// G2 probe: does v0.47.2 pass &local as pointer to extern?
module probe_g2
extern "C" { fn xvk_probe_out(out_w: *Int32, out_h: *Int32); }
fn main() -> Int {
  var w: Int32 = 0;
  var h: Int32 = 0;
  unsafe { xvk_probe_out(&w, &h); }
  return 0;
}
