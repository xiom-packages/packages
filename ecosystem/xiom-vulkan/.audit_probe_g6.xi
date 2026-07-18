// G6 probe: .data local rebind + reuse → bogus move or crash?
module probe_g6
extern "C" { fn xvk_probe_out(w: *Int32, h: *Int32); fn xvk_probe_int(a: Int, b: Int); }
fn main() -> Int {
  var wh = Vec[Int32].new();
  wh.push(0); wh.push(0);
  let base = wh.data;
  unsafe { xvk_probe_int(base as Int, base as Int); }
  return 0;
}
