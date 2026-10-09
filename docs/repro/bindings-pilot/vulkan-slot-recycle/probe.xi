// B-11 repro: out-param slot memory written by a Vulkan-heavy C call is
// recycled before XIOM can read it (v0.64.2 runtime).
//
// Run (workdir = this directory; the bridge comes from the xiom.vma package):
//   xiom --run probe.xi --c-source <repo>/packages/xiom-vma/src/vma_bridge.cpp
//
// Observed (2026-10-09): the bridge's own volatile readback inside C shows
// *size=65536 at return, but the first XIOM read of the middle slot returns
// 0 (byte reads can show unrelated recycled content; u32 and byte reads can
// even disagree within one call). The heap and verify slots read correctly;
// only the middle slot is affected in every run. Trivial/malloc-heavy/
// loader-only/instance-only C variants do NOT reproduce it -- the Vulkan
// device+allocator+mapping sequence does.
//
// The xiom.vma package avoids the pattern with a packed return value
// (vmaprobe_run_packed); the slot variant is kept in the bridge solely as
// this reproduction.

module vma_slot_recycle_probe

use xiom.io;
use xiom.ffi;

extern "C" {
  fn vmaprobe_run(out_heap_count: *UInt8, out_alloc_size: *UInt8, out_verify: *UInt8) -> Int32;
}

fn slot() -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 8 {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn rd(s: &Vec[UInt8]) -> Int {
  return ffi.ptr_read_u32_le(s.as_mut_ptr());
}

fn wr(s: &Vec[UInt8], v: Int) {
  ffi.ptr_write_u32_le(s.as_mut_ptr(), v);
}

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let d = v % 10;
    v = v / 10;
    if d == 0 { buf = "0" + buf; }
    elif d == 1 { buf = "1" + buf; }
    elif d == 2 { buf = "2" + buf; }
    elif d == 3 { buf = "3" + buf; }
    elif d == 4 { buf = "4" + buf; }
    elif d == 5 { buf = "5" + buf; }
    elif d == 6 { buf = "6" + buf; }
    elif d == 7 { buf = "7" + buf; }
    elif d == 8 { buf = "8" + buf; }
    elif d == 9 { buf = "9" + buf; }
  }
  if neg { return "-" + buf; }
  return buf;
}

fn main() -> Int {
  unsafe {
    var a = slot();
    var b = slot();
    var c = slot();
    wr(&a, 777);
    wr(&b, 888);
    wr(&c, 999);
    let rc = vmaprobe_run(a.as_mut_ptr(), b.as_mut_ptr(), c.as_mut_ptr());
    io.println("inside: a=" + i2s(rd(&a)) + " b=" + i2s(rd(&b)) + " c=" + i2s(rd(&c))
      + " rc=" + i2s(rc as Int));
    // Expected without the bug: a=3 b=65536 c=1.  Observed: b=0.
  }
  return 0;
}
