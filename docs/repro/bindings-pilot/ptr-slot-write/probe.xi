// B-16 repro (v0.64.3): ffi.ptr_write_* into an XIOM-owned slot vs
// byte-indexed writes, both followed by a foreign call reading the slot.
//
// Observed during ixom.sdl3 0.12.0: SDL_OpenAudioDeviceStream rejected the
// SDL_AudioSpec built with three ffi.ptr_write_u32_le calls ("Parameter
// 'src_spec->channels' is invalid") while the identical values written with
// byte-indexed stores worked.  Both runs print THEIR sum here.
//
// Run: & scripts\xiom.ps1 --run <abs>\probe.xi --c-source <abs>\host.c
// Expected on v0.64.3: ptr_write_sum=66 and byte_index_sum=66 for a healthy
// compiler; the SDL case suggests the ptr_write path can lose fields.

module ptr_slot_write_probe

use xiom.io;
use xiom.convert;
use xiom.ffi;

extern "C" {
  fn xt_sum3(p: *UInt8) -> Int32;
}

fn slot(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn wr32(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: buf.len() >= off + 4
{
  buf[off + 0] = ( v        & 0xFF) as UInt8;
  buf[off + 1] = ((v >>  8) & 0xFF) as UInt8;
  buf[off + 2] = ((v >> 16) & 0xFF) as UInt8;
  buf[off + 3] = ((v >> 24) & 0xFF) as UInt8;
}

fn main() -> Int {
  // A: ffi.ptr_write path (as used by the first audio wrapper build).
  var a = slot(12);
  unsafe {
    ffi.ptr_write_u32_le(a.as_mut_ptr(), 11);
    ffi.ptr_write_u32_le(a.as_mut_ptr() + 4, 22);
    ffi.ptr_write_u32_le(a.as_mut_ptr() + 8, 33);
  }
  let ra = unsafe { xt_sum3(a.as_mut_ptr()) as Int };
  io.println("ptr_write_sum=" + int_to_string(ra));
  io.flush_stdout();

  // B: byte-indexed writes (the lane's proven slot discipline).
  var b = slot(12);
  wr32(&mut b, 0, 11);
  wr32(&mut b, 4, 22);
  wr32(&mut b, 8, 33);
  let rb = unsafe { xt_sum3(b.as_mut_ptr()) as Int };
  io.println("byte_index_sum=" + int_to_string(rb));
  io.flush_stdout();
  return 0;
}
