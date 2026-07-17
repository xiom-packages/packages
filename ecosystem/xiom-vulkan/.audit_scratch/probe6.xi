// probe6 — alloc + ptr.write marshalling path for FFI
module probe6

use xiom.alloc;
use xiom.ptr;

extern "C" {
  fn xvk_take_floats(data: *UInt8, count: Int);
  fn xvk_probe_out(w: *UInt8, h: *UInt8);
}

fn main() -> Int {
  // 3 Float32 values via raw alloc
  let buf = alloc.alloc(12);
  let f0: Float32 = 1.5;
  let f1: Float32 = 2.5;
  let f2: Float32 = 3.5;
  unsafe {
    let p0 = buf as *Float32;
    ptr.write(p0, f0);
    let p1 = ptr.add(p0, 1);
    ptr.write(p1, f1);
    let p2 = ptr.add(p0, 2);
    ptr.write(p2, f2);
    xvk_take_floats(buf, 3);
  }

  // out-params via alloc'd Int32 slots
  let wp = alloc.alloc(4);
  let hp = alloc.alloc(4);
  var w: Int32 = 0;
  var h: Int32 = 0;
  unsafe {
    xvk_probe_out(wp, hp);
    w = ptr.read(wp as *Int32);
    h = ptr.read(hp as *Int32);
    alloc.dealloc(wp, 4);
    alloc.dealloc(hp, 4);
    alloc.dealloc(buf, 12);
  }
  if w == 800 && h == 600 { return 0; }
  return 7;
}
