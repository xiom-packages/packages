// probe12 — Int-family Vec push + .data contents to C; staging scalar roundtrip
module probe12

extern "C" {
  fn xvk_recv_i32s(data: Int, count: Int);
  fn xvk_recv_i64s(data: Int, count: Int);
  fn xvk_staging_create(bytes: Int) -> Int;
  fn xvk_staging_destroy(st: Int);
  fn xvk_staging_set_f32(st: Int, index: Int, value: Float32);
  fn xvk_staging_get_f32(st: Int, index: Int) -> Float32;
  fn xvk_staging_set_i32(st: Int, index: Int, value: Int);
  fn xvk_staging_get_i32(st: Int, index: Int) -> Int;
  fn xvk_staging_set_i64(st: Int, index: Int, value: Int);
  fn xvk_staging_check_f32(st: Int, index: Int, expected: Float32) -> Int;
}

fn main() -> Int {
  // 1. Vec[Int32] push-built → .data to C
  var vi = Vec[Int32].new();
  vi.push(11);
  vi.push(22);
  vi.push(33);
  unsafe { xvk_recv_i32s(vi.data, vi.len()); }

  // 2. Vec[Int] push-built → .data to C
  var vh = Vec[Int].new();
  vh.push(1111);
  vh.push(2222);
  unsafe { xvk_recv_i64s(vh.data, vh.len()); }

  // 3. staging roundtrip: f32 + i32 through pure scalar FFI
  let st = unsafe { xvk_staging_create(64) };
  if st == 0 { return 1; }
  unsafe {
    xvk_staging_set_f32(st, 0, 1.5);
    xvk_staging_set_f32(st, 1, 2.5);
    xvk_staging_set_i32(st, 8, 800);
    xvk_staging_set_i64(st, 5, 123456789);
  }
  let f0 = unsafe { xvk_staging_get_f32(st, 0) };
  let ok0 = unsafe { xvk_staging_check_f32(st, 0, 1.5) };
  let ok1 = unsafe { xvk_staging_check_f32(st, 1, 2.5) };
  let i8v = unsafe { xvk_staging_get_i32(st, 8) };
  unsafe { xvk_staging_destroy(st); }
  if ok0 != 1 { return 2; }
  if ok1 != 1 { return 3; }
  if f0 != 1.5 { return 4; }
  if i8v != 800 { return 5; }
  return 0;
}
