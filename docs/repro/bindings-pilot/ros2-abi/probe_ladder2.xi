// ABI probe #4: sret + 40B-by-value cases only (c2 removed).
module probe_ladder2

use xiom.ffi.dl;
use xiom.convert;
use xiom.io;

type Alloc5 = {
  allocate: Int;
  deallocate: Int;
  reallocate: Int;
  zero_allocate: Int;
  state: Int;
}

type Pair2 = {
  a: Int;
  b: Int;
}

fn say(s: Str) {
  io.println(s);
  io.flush_stdout();
}

pub fn main() -> Int {
  let h = dl.dl_open("C:/Users/lefte/AppData/Local/Temp/kilo/ros2-abi/probe.dll");
  if !h.is_ok {
    say("load failed: " + h.error);
    return 1;
  }
  let handle = h.value;
  let al = Alloc5{ allocate: 11; deallocate: 22; reallocate: 33; zero_allocate: 44; state: 55 };

  let m2 = dl.dl_sym(handle, "probe_make2");
  if m2.is_ok {
    say("c3 16B-record-sret: calling");
    unsafe {
      let f = m2.value as fn(Int) -> Pair2;
      let r = f(500);
      say("c3 fields " + convert.int_to_string(r.a) + "," + convert.int_to_string(r.b));
    }
  }

  let m5 = dl.dl_sym(handle, "probe_make5");
  if m5.is_ok {
    say("c4 40B-record-sret: calling");
    unsafe {
      let f = m5.value as fn(Int) -> Alloc5;
      let r = f(1000);
      say("c4 fields " + convert.int_to_string(r.allocate) + "," + convert.int_to_string(r.state));
    }
  }

  let s5 = dl.dl_sym(handle, "probe_sum5");
  if s5.is_ok {
    say("c5 40B-record-by-value: calling");
    unsafe {
      let f = s5.value as fn(Alloc5) -> Int;
      let r = f(al);
      say("c5 returned " + convert.int_to_string(r));
    }
  }

  say("done");
  return 0;
}
