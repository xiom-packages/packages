// Foreign-thread callback ABI probe (miniaudio handle-surface gate).
//
// Q: can a bare top-level XIOM fn name be handed to C via a fn-typed extern
// param and be INVOKED FROM A C THREAD OTHER THAN THE XIOM MAIN THREAD, while
// the main thread keeps calling into C (and, in arm 2, executing XIOM code)?
//
// The C worker writes 0x00 into the buffer, calls the XIOM handler on it and
// counts a marker hit when the handler wrote buf[0]=171 / buf[63]=205.
//
// Run (from repo root):
//   $env:XIOM_COMPILER = "$env:LOCALAPPDATA\xiom.new\bin\xiom.exe"
//   & $env:XIOM_COMPILER --run <abs>\probe_xthread.xi --c-source <abs>\cbthread.c

module xthread_render_probe

use xiom.io;
use xiom.convert;
use xiom.ffi;

extern "C" {
  fn xtc_set(f: fn(*UInt8, Int32) -> Unit) -> Int32;
  fn xtc_start() -> Int32;
  fn xtc_stop() -> Int32;
  fn xtc_calls() -> Int32;
  fn xtc_hits() -> Int32;
  fn xtc_burn(ms: Int32) -> Int32;
  fn xtc_plus_one(x: Int32) -> Int32;
}

// Safe wrappers (the module pattern).
fn xcb_set(f: fn(*UInt8, Int32) -> Unit) -> Int
  requires: true
{
  unsafe { return xtc_set(f) as Int; }
}

fn xcb_start() -> Int
  requires: true
{
  unsafe { return xtc_start() as Int; }
}

fn xcb_stop() -> Int
  requires: true
{
  unsafe { return xtc_stop() as Int; }
}

fn xcb_calls() -> Int
  requires: true
{
  unsafe { return xtc_calls() as Int; }
}

fn xcb_hits() -> Int
  requires: true
{
  unsafe { return xtc_hits() as Int; }
}

fn xcb_burn(ms: Int) -> Int
  requires: ms >= 0
{
  unsafe { return xtc_burn(ms as Int32) as Int; }
}

fn xcb_plus_one(x: Int) -> Int
  requires: true
{
  unsafe { return xtc_plus_one(x as Int32) as Int; }
}

// Module-level observation state (mutated on the C worker thread).
var xcb_seq: Int = 0;
var xcb_last_frames: Int = 0;

// The render handler: writes the marker pattern into the C-owned buffer.
fn xcb_render(out: *UInt8, frames: Int32) -> Unit {
  xcb_seq = xcb_seq + 1;
  xcb_last_frames = frames as Int;
  unsafe {
    ffi.ptr_write_u8(out, 171);
    ffi.ptr_write_u8((out as Int + 63) as *UInt8, 205);
  }
}

// Pure XIOM work for the overlap arm.
fn xcb_local_sum(n: Int) -> Int {
  var acc = 0;
  var i = 0;
  while i < n {
    acc = acc + i;
    i = i + 1;
  }
  return acc;
}

fn main() -> Int {
  var failed = 0;

  // Arm 1: worker thread invokes the XIOM handler; main sits in C.
  let s0 = xcb_set(xcb_render);
  let s1 = xcb_start();
  let ig = xcb_burn(300);
  let calls1 = xcb_calls();
  let hits1 = xcb_hits();
  let ig2 = xcb_stop();
  let seq1 = xcb_seq;
  let f1 = calls1 > 0 && hits1 == calls1 && seq1 >= calls1;
  io.println("arm1 set=" + int_to_string(s0) + " start=" + int_to_string(s1)
    + " calls=" + int_to_string(calls1) + " hits=" + int_to_string(hits1)
    + " xiom_seq=" + int_to_string(seq1) + " frames=" + int_to_string(xcb_last_frames));
  if !f1 { failed = failed + 1; }

  // Arm 2: worker runs concurrently while the main thread executes XIOM code
  // (local fn + extern calls interleaved) and C burns.
  let c0 = xcb_seq;
  let ig3 = xcb_start();
  var i = 0;
  var acc = 0;
  while i < 200 {
    acc = acc + xcb_local_sum(50);
    acc = acc + xcb_plus_one(i);
    acc = acc + xcb_hits() * 0;
    i = i + 1;
  }
  let ig4 = xcb_burn(100);
  let calls2 = xcb_calls();
  let hits2 = xcb_hits();
  let ig5 = xcb_stop();
  let delta = xcb_seq - c0;
  let f2 = calls2 > 0 && hits2 == calls2 && delta >= calls2;
  io.println("arm2 acc=" + int_to_string(acc) + " calls=" + int_to_string(calls2)
    + " hits=" + int_to_string(hits2) + " xiom_delta=" + int_to_string(delta));
  if !f2 { failed = failed + 1; }

  var verdict = "FAIL";
  if failed == 0 { verdict = "PASS"; }
  io.println("xthread-cb: " + verdict);
  io.flush_stdout();
  return failed;
}
