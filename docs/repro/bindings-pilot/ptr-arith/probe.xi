// B-17 repro (v0.64.3): raw-pointer arithmetic `*UInt8 + Int` compiles to
// a WILD address -- not base+offset.  Even `base + 0` is wrong.  Address
// arithmetic kept in `Int` (the loader idiom) is correct.
//
// Run (pure XIOM, no C source, no DLL):
//   . scripts\xiom.ps1
//   $tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
//   & $tool.Xiom --run <abs>\probe.xi
//
// Healthy compiler prints d0=0, d1=1, d4=4, d8=8, d12=12, d16=16, d24=24,
// d100=100 (deltas of (base + N) - base).  On v0.64.3 the pointer-typed
// deltas are wild and vary per process (ASLR), while `int-typed d12` is the
// exact 12.  The wild values are addresses of unrelated memory; passing
// such a pointer to a foreign call makes C write into unowned memory
// (silent corruption; observed as nondeterministic heap corruption).

module ptr_arith_probe

use xiom.io;
use xiom.convert;

fn slot_new(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn main() -> Int {
  unsafe {
    var slot = slot_new(32);
    let base = slot.as_mut_ptr();
    let ib = base as Int;
    io.println("base=" + int_to_string(ib));
    io.println("d0=" + int_to_string(((base + 0) as Int) - ib));
    io.println("d1=" + int_to_string(((base + 1) as Int) - ib));
    io.println("d4=" + int_to_string(((base + 4) as Int) - ib));
    io.println("d8=" + int_to_string(((base + 8) as Int) - ib));
    io.println("d12=" + int_to_string(((base + 12) as Int) - ib));
    io.println("d16=" + int_to_string(((base + 16) as Int) - ib));
    io.println("d24=" + int_to_string(((base + 24) as Int) - ib));
    io.println("d100=" + int_to_string(((base + 100) as Int) - ib));
    // Control: the same offsets with Int-typed address math are exact.
    io.println("int-typed d12=" + int_to_string((base as Int + 12) - ib));
    // Second slot: same shape, second allocation (values differ -> each
    // miscompiled expression reads unrelated memory, not a fixed offset).
    var slot2 = slot_new(32);
    let base2 = slot2.as_mut_ptr();
    let ib2 = base2 as Int;
    io.println("d12-again=" + int_to_string(((base2 + 12) as Int) - ib2));
    io.flush_stdout();
  }
  return 0;
}
