// ABI probe #5: pointer-pretend shape. C functions have BY-VALUE struct params
// (probe_sum5(Alloc5), probe_sum2(Pair2,int64)); we call through fn-casts that
// declare those params as *UInt8, passing the address of an XIOM-owned slot.
// On MS x64 / AArch64 (by-ref-copy aggregate ABIs) this must return the same
// values as the C-side computation: 165 and 17036.
module probe_pretend

use xiom.ffi.dl;
use xiom.convert;
use xiom.io;

fn say(s: Str) {
  io.println(s);
  io.flush_stdout();
}

fn wr_u64_le(buf: &mut Vec[UInt8], off: Int, v: Int) {
  buf[off] = (v & 255) as UInt8;
  buf[off + 1] = ((v >> 8) & 255) as UInt8;
  buf[off + 2] = ((v >> 16) & 255) as UInt8;
  buf[off + 3] = ((v >> 24) & 255) as UInt8;
  buf[off + 4] = ((v >> 32) & 255) as UInt8;
  buf[off + 5] = ((v >> 40) & 255) as UInt8;
  buf[off + 6] = ((v >> 48) & 255) as UInt8;
  buf[off + 7] = ((v >> 56) & 255) as UInt8;
}

pub fn main() -> Int {
  let h = dl.dl_open("C:/Users/lefte/AppData/Local/Temp/kilo/ros2-abi/probe.dll");
  if !h.is_ok {
    say("load failed: " + h.error);
    return 1;
  }
  let handle = h.value;

  let s5 = dl.dl_sym(handle, "probe_sum5");
  if s5.is_ok {
    say("p1 by-value-40B via pointer-pretend: calling");
    var slot = Vec[UInt8].with_len(40);
    wr_u64_le(&mut slot, 0, 11);
    wr_u64_le(&mut slot, 8, 22);
    wr_u64_le(&mut slot, 16, 33);
    wr_u64_le(&mut slot, 24, 44);
    wr_u64_le(&mut slot, 32, 55);
    unsafe {
      let f = s5.value as fn(*UInt8) -> Int;
      let r = f(slot.as_mut_ptr());
      say("p1 returned " + convert.int_to_string(r) + " (want 165)");
    }
  }

  let s2 = dl.dl_sym(handle, "probe_sum2");
  if s2.is_ok {
    say("p2 by-value-16B via pointer-pretend: calling");
    var slot = Vec[UInt8].with_len(16);
    wr_u64_le(&mut slot, 0, 17);
    wr_u64_le(&mut slot, 8, 29);
    unsafe {
      let f = s2.value as fn(*UInt8, Int) -> Int;
      let r = f(slot.as_mut_ptr(), 7);
      say("p2 returned " + convert.int_to_string(r) + " (want 17036)");
    }
  }

  say("done");
  return 0;
}
