// B-27 repro: `ptr as Int` cast combined with a second statement in one
// `unsafe` block -> undefined IR value (codegen failure on v0.64.4).
// Expected: "clang failed with exit code 1 / use of undefined value".
// The fixed variant is probe_fixed.xi.
module owned_slot_cast_probe

use xiom.io;

fn slot_new(n: Int) -> Vec[UInt8]
  requires: n > 0
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn fvec(n: Int) -> Vec[Float32]
  requires: n > 0
{
  var v: Vec[Float32] = Vec[Float32].new();
  var i: Int = 0;
  while i < n {
    v.push(0.0);
    i = i + 1;
  }
  return v;
}

fn s_w32(buf: &mut Vec[UInt8], idx: Int, v: Int)
  requires: idx >= 0
  requires: idx + 3 < buf.len()
{
  buf[idx] = (v & 0xFF) as UInt8;
  buf[idx + 1] = ((v >> 8) & 0xFF) as UInt8;
  buf[idx + 2] = ((v >> 16) & 0xFF) as UInt8;
  buf[idx + 3] = ((v >> 24) & 0xFF) as UInt8;
}

fn s_w64(buf: &mut Vec[UInt8], idx: Int, v: Int)
  requires: idx >= 0
  requires: idx + 7 < buf.len()
{
  s_w32(buf, idx, v & 0xFFFFFFFF);
  s_w32(buf, idx + 4, (v >> 32) & 0xFFFFFFFF);
}

pub type Fbuf = {
  num_channels: Int;
  num_samples: Int;
  slot: Vec[UInt8];
  ptrs: Vec[UInt8];
  data: Vec[Float32];
}

fn fbuf_new(channels: Int, samples: Int) -> Fbuf
  requires: channels > 0
  requires: samples > 0
{
  var data = fvec(channels * samples);
  var base = 0;
  unsafe {
    base = data.as_mut_ptr() as Int;
  }
  var ptrs = slot_new(channels * 8);
  var slot = slot_new(16);
  s_w32(&mut slot, 0, channels);
  s_w32(&mut slot, 4, samples);
  unsafe {
    let pa = ptrs.as_mut_ptr() as Int;
    s_w64(&mut slot, 8, pa);
  }
  return Fbuf{ num_channels: channels; num_samples: samples; slot: slot; ptrs: ptrs; data: data };
}

fn main() -> Int {
  var b = fbuf_new(2, 256);
  io.println("ch=" + to_string(b.num_channels));
  return 0;
}
