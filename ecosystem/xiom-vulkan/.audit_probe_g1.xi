// G1 probe: does v0.47.2 accept Vec→Ptr, Array→Ptr, Int→Ptr casts?
module probe_g1
extern "C" { fn xvk_probe_bytes(data: *UInt8, size: Int); fn xvk_probe_i32(data: *Int32, count: Int32); fn xvk_probe_i64(data: *Int, count: Int32); }
fn main() -> Int {
  var v: Vec[Float32] = [1.0, 2.0];
  unsafe { xvk_probe_bytes(v as *UInt8, v.len() * 4); }
  var vi: Vec[Int32] = [1, 2];
  unsafe { xvk_probe_i32(vi as *Int32, vi.len() as Int32); }
  var vh: Vec[Int] = [10, 20];
  unsafe { xvk_probe_i64(vh as *Int, vh.len() as Int32); }
  return 0;
}
