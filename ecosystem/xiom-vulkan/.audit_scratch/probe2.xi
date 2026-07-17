// probe2 — fixed-array & direct-reference FFI patterns
module probe2

extern "C" {
  fn xvk_probe_bytes(data: *UInt8, size: Int);
  fn xvk_probe_i32(data: *Int32, count: Int32);
  fn xvk_probe_out(out_w: *Int32, out_h: *Int32);
}

fn main() -> Int {
  // Pattern A: fixed array + address-of + cast (stdlib net.xi pattern)
  var buf: [64]UInt8;
  unsafe { xvk_probe_bytes(&buf as *UInt8, 64); }

  // Pattern B: fixed Int32 array + cast
  var arr32: [8]Int32;
  unsafe { xvk_probe_i32(&arr32 as *Int32, 8 as Int32); }

  // Pattern C: pass &var directly to pointer param (no cast)
  var w: Int32 = 0;
  var h: Int32 = 0;
  unsafe { xvk_probe_out(&w, &h); }

  return 0;
}
