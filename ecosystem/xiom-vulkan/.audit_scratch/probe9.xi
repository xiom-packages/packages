// probe9 — local deref helpers: the candidate production marshalling layer
module probe9

use xiom.alloc;

extern "C" {
  fn xvk_recv_i32s(data: *UInt8, count: Int);
  fn xvk_recv_f32s(data: *UInt8, count: Int);
}

fn write_i32(base: *UInt8, byte_offset: Int, v: Int32) {
  unsafe {
    let p = (base + byte_offset) as *Int32;
    *p = v;
  }
}

fn read_i32(base: *UInt8, byte_offset: Int) -> Int32 {
  unsafe {
    let p = (base + byte_offset) as *Int32;
    return *p;
  }
}

fn write_f32(base: *UInt8, byte_offset: Int, v: Float32) {
  unsafe {
    let p = (base + byte_offset) as *Float32;
    *p = v;
  }
}

fn read_f32(base: *UInt8, byte_offset: Int) -> Float32 {
  unsafe {
    let p = (base + byte_offset) as *Float32;
    return *p;
  }
}

fn main() -> Int {
  // Int32 roundtrip through C
  let ib = alloc.alloc(8);
  write_i32(ib, 0, 123 as Int32);
  write_i32(ib, 4, 456 as Int32);
  unsafe { xvk_recv_i32s(ib, 2); }          // C prints then writes 800, 600
  let w = read_i32(ib, 0);
  let h = read_i32(ib, 4);
  alloc.dealloc(ib, 8);
  if w != 800 { return 1; }
  if h != 600 { return 2; }

  // Float32 array to C
  let fb = alloc.alloc(12);
  write_f32(fb, 0, 1.5);
  write_f32(fb, 4, 2.5);
  write_f32(fb, 8, 3.5);
  let c0 = read_f32(fb, 0);
  if c0 != 1.5 { return 3; }
  unsafe { xvk_recv_f32s(fb, 3); }
  alloc.dealloc(fb, 12);
  return 0;
}
