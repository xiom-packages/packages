// probe3 — extern params declared as Int (pointer-as-handle pattern)
module probe3

extern "C" {
  fn xvk_probe_bytes(data: Int, size: Int);
  fn xvk_probe_out(out_w: Int, out_h: Int);
  fn xvk_probe_mixed(app: Int, vals: Int, count: Int32) -> Int32;
}

fn bool_to_int32(b: Bool) -> Int32 {
  if b { return 1 as Int32; }
  return 0 as Int32;
}

fn main() -> Int {
  // Vec data pointer via .data field (checker: Int)
  var v: Vec[Float32] = [1.0, 2.0, 3.0];
  unsafe { xvk_probe_bytes(v.data, v.len() * 4); }

  // out-params: &local passed to Int param
  var w: Int32 = 0;
  var h: Int32 = 0;
  unsafe { xvk_probe_out(&w, &h); }

  // Int32 count + bool conversion
  var vi: Vec[Int32] = [];
  let flag = true;
  let r: Int32 = unsafe { xvk_probe_mixed(bool_to_int32(flag) as Int, vi.data, vi.len() as Int32) };
  return r as Int;
}
