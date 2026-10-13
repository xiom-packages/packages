// B-25 repro: Int <-> pointer cast fidelity on v0.64.4.
// Companion C host: ptrhost.c (pt_see_ptr / pt_see_int).
//
// Run (from the repo root; absolute paths):
//   . scripts\xiom.ps1
//   $tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
//   & $tool.Xiom --run <abs>\probe.xi --c-source <abs>\ptrhost.c

module ptr_cast_probe

use xiom.io;
use xiom.convert;

extern "C" {
  fn pt_see_ptr(p: *UInt8) -> Int64;
  fn pt_see_int(p: Int64) -> Int64;
}

fn main() -> Int {
  io.println("=== B-25 ptr-cast probe (v0.64.4) ===");
  io.flush_stdout();

  var buf: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 8 { buf.push(0 as UInt8); i = i + 1; }

  // A KNOWN pointer (the buffer data address).
  let p1 = buf.as_mut_ptr();
  let see_p1 = unsafe { pt_see_ptr(p1) };

  // Pointer -> Int -> Int64 param (the `obj: Int` generated-wrapper path).
  let as_int = unsafe { p1 as Int };
  let see_int = unsafe { pt_see_int(as_int as Int64) };

  // Int -> pointer cast (the `x as *UInt8` handle path).
  let p2 = unsafe { as_int as *UInt8 };
  let see_p2 = unsafe { pt_see_ptr(p2) };

  io.println("true_ptr   = " + to_string(see_p1));
  io.println("int_param  = " + to_string(see_int));
  io.println("cast_ptr   = " + to_string(see_p2));
  if see_int == see_p1 {
    io.println("int-param path: FIDELITY OK (pointer -> Int -> Int64 preserves)");
  } else {
    io.println("int-param path: LOSSY");
  }
  if see_p2 == see_p1 {
    io.println("cast path: FIDELITY OK (Int -> *UInt8 preserves)");
  } else {
    io.println("cast path: LOSSY -- Int as *UInt8 does NOT preserve the value (B-25)");
  }
  return 0;
}
