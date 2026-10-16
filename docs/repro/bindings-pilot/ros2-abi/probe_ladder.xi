// ABI probe #3: case ladder inside unsafe blocks. Process stops at the first
// faulting call (silent exit 0), so the last printed marker names the shape.
module probe_ladder

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
  let al = Alloc5{ allocate: 11; deallocate: 22; reallocate: 33; zero_allocate: 44; state: 55 };
  let p = Pair2{ a: 17; b: 29 };

  let s5p = dl.dl_sym(handle, "probe_sum5p");
  if s5p.is_ok {
    say("c1 pointer-to-40B-slot: calling");
    var slot = Vec[UInt8].with_len(40);
    wr_u64_le(&mut slot, 0, 11);
    wr_u64_le(&mut slot, 8, 22);
    wr_u64_le(&mut slot, 16, 33);
    wr_u64_le(&mut slot, 24, 44);
    wr_u64_le(&mut slot, 32, 55);
    unsafe {
      let f = s5p.value as fn(*UInt8) -> Int;
      let r = f(slot.as_mut_ptr());
      say("c1 returned " + convert.int_to_string(r));
    }
  }

  let s2 = dl.dl_sym(handle, "probe_sum2");
  if s2.is_ok {
    say("c2 16B-record-by-value: calling");
    unsafe {
      let f = s2.value as fn(Pair2, Int) -> Int;
      let r = f(p, 7);
      say("c2 returned " + convert.int_to_string(r));
    }
  }

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
