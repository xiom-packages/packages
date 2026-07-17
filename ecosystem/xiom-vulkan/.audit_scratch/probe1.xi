// probe1 — test Vec->pointer patterns for extern FFI under xiomc 0.46
module probe1

extern "C" {
  fn xvk_probe_bytes(data: *UInt8, size: Int);
  fn xvk_probe_i32(data: *Int32, count: Int32);
  fn xvk_probe_iptr(data: *Int, count: Int32);
  fn xvk_probe_out(out_w: *Int32, out_h: *Int32);
}

fn main() -> Int {
  // Pattern A: Vec.data field access + pointer cast
  var v: Vec[Float32] = [1.0, 2.0, 3.0];
  unsafe { xvk_probe_bytes(v.data as *UInt8, v.len() * 4); }

  // Pattern B: Vec[Int32].data as *Int32
  var vi: Vec[Int32] = [];
  unsafe { xvk_probe_i32(vi.data as *Int32, vi.len() as Int32); }

  // Pattern C: Vec[Int].data as *Int
  var vp: Vec[Int] = [1, 2];
  unsafe { xvk_probe_iptr(vp.data as *Int, vp.len() as Int32); }

  // Pattern D: address-of local with explicit pointer cast
  var w: Int32 = 0;
  var h: Int32 = 0;
  unsafe { xvk_probe_out(&w as *Int32, &h as *Int32); }

  return 0;
}
