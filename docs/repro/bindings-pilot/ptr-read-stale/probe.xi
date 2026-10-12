// B-24 minimal repro (v0.64.4): an OUT-SLOT write performed by a C extern
// call is intermittently not observed by a subsequent
// `ffi.ptr_read_u64_le` on the SAME owned slot: the read returns the stale
// zero.  Byte-indexed reads over the same Vec see the correct value.
//
// Run (via a package runner, or):
//   . scripts\xiom.ps1
//   $tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
//   & $tool.Xiom --run <abs>\probe.xi --c-source <abs>\host.c
module ptr_read_stale_probe

use xiom.io;
use xiom.ffi;

extern "C" {
  fn poke8(dst: *UInt8, v: UInt64);
}

fn mk_slot(n: Int) -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n { v.push(0 as UInt8); i = i + 1; }
  return v;
}

fn round_ffi(i: Int) -> Int {
  var slot = mk_slot(8);
  unsafe { poke8(slot.as_mut_ptr(), (1000 + i) as UInt64); }
  let got = unsafe { ffi.ptr_read_u64_le(slot.as_mut_ptr()) };
  let want = 1000 + i;
  if got != want {
    io.println("ffi read  round " + to_string(i) + ": got=" + to_string(got) + " want=" + to_string(want));
    return 1;
  }
  return 0;
}

fn le64(v: Vec[UInt8], off: Int) -> Int {
  return (v[off] as Int) | ((v[off + 1] as Int) << 8)
    | ((v[off + 2] as Int) << 16) | ((v[off + 3] as Int) << 24)
    | ((v[off + 4] as Int) << 32) | ((v[off + 5] as Int) << 40)
    | ((v[off + 6] as Int) << 48) | ((v[off + 7] as Int) << 56);
}

fn round_bytes(i: Int) -> Int {
  var slot = mk_slot(8);
  unsafe { poke8(slot.as_mut_ptr(), (2000 + i) as UInt64); }
  let got = le64(slot, 0);
  let want = 2000 + i;
  if got != want {
    io.println("byte read round " + to_string(i) + ": got=" + to_string(got) + " want=" + to_string(want));
    return 1;
  }
  return 0;
}

fn main() -> Int {
  var bad_ffi = 0;
  var bad_bytes = 0;
  var i = 0;
  while i < 400 {
    bad_ffi = bad_ffi + round_ffi(i);
    bad_bytes = bad_bytes + round_bytes(i);
    i = i + 1;
  }
  io.println("ptr_read_stale: ffi_bad=" + to_string(bad_ffi)
    + " byte_bad=" + to_string(bad_bytes) + " of 400");
  return bad_ffi + bad_bytes;
}
