// G12c: Int32 push-built Vec + as *Int32 → C reads correct values?
module probe_g12c
extern "C" {
  fn xvk_check_i32s(data: *Int32, count: Int) -> Int;
}
fn main() -> Int {
  var v = Vec[Int32].new();
  v.push(111); v.push(222); v.push(333);
  let ok = unsafe { xvk_check_i32s(v as *Int32, v.len()) };
  if ok != 1 { return 1; }
  return 0;
}
