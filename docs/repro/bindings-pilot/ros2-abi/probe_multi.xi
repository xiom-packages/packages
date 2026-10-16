// ABI probe #6: multi-arg shapes (9-arg wait_set_init-like, 7-arg timer_init2-like,
// 3-arg clock_init-like) with the by-value 40B allocator passed via pointer-pretend.
// Expected: ws9 = 1000+1+2+3+4+5+6+7000 + (11+22+33+44+55) = 8180? compute:
//   ws=1000, a..f=1..6 (21), ctx=7000, alloc sum=165 -> 8186
//   t7: t=100,cl=200,x=300,p=400,cb=500,au=600 + (11+55) -> 2166
//   c3: ty=3 + cl=900 + (11+55) -> 969
module probe_multi

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
  var al = Vec[UInt8].with_len(40);
  wr_u64_le(&mut al, 0, 11);
  wr_u64_le(&mut al, 8, 22);
  wr_u64_le(&mut al, 16, 33);
  wr_u64_le(&mut al, 24, 44);
  wr_u64_le(&mut al, 32, 55);
  let alptr = al.as_mut_ptr() as Int;

  let s9 = dl.dl_sym(handle, "probe_ws9");
  if s9.is_ok {
    say("m1 9-arg ws9 calling");
    unsafe {
      let f = s9.value as fn(*UInt8, Int, Int, Int, Int, Int, Int, *UInt8, *UInt8) -> Int;
      let r = f(1000 as *UInt8, 1, 2, 3, 4, 5, 6, 7000 as *UInt8, alptr as *UInt8);
      say("m1 returned " + convert.int_to_string(r) + " (want 8186)");
    }
  }

  let t7 = dl.dl_sym(handle, "probe_t7");
  if t7.is_ok {
    say("m2 7-arg t7 calling");
    unsafe {
      let f = t7.value as fn(*UInt8, *UInt8, *UInt8, Int, Int, *UInt8, Int) -> Int;
      let r = f(100 as *UInt8, 200 as *UInt8, 300 as *UInt8, 400, 500, alptr as *UInt8, 600);
      say("m2 returned " + convert.int_to_string(r) + " (want 2166)");
    }
  }

  let c3 = dl.dl_sym(handle, "probe_c3");
  if c3.is_ok {
    say("m3 3-arg c3 calling");
    unsafe {
      let f = c3.value as fn(Int, *UInt8, *UInt8) -> Int;
      let r = f(3, 900 as *UInt8, alptr as *UInt8);
      say("m3 returned " + convert.int_to_string(r) + " (want 969)");
    }
  }

  say("done");
  return 0;
}
