// B-20 repro (v0.64.3): a foreign pointer returned by an extern
// (`*UInt8`) cast to Int and re-derived with Int address math reads
// ZEROS from the XIOM side, while the C side reads the same buffer
// correctly.  No crash, no diagnostic: silent zeros.
//
// Run (fast; no package needed):
//   . scripts\xiom.ps1
//   $tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
//   & $tool.Xiom --run <abs>\probe.xi --c-source <abs>\host.c
//
// Healthy behavior: XIOM u32[0]=1065353216 (1.0f bits) u32[1]=1073741824
// (2.0f bits), matching the C-side readers.
// Observed on v0.64.3: C-side perfect (sum=3212836864 overflow-free parts:
// use the per-element readers), XIOM u32[0]=0 u32[1]=0 -- every read is 0.
// The working path is: C copies into an XIOM-owned slot
// (out-param pointer) + byte-indexed Vec reads; see docs/BINDINGS-COMPILER-
// FINDINGS.md B-20 and the xiom.assimp 0.8.0 copy getters.

module foreign_ptr_read_probe

use xiom.io;
use xiom.convert;
use xiom.ffi;

extern "C" {
  fn xt_buf_ptr() -> *UInt8;
  fn xt_buf_u32(i: Int) -> Int32;
}

fn main() -> Int {
  unsafe {
    io.println("C-side   u32[0]=" + to_string(xt_buf_u32(0) as Int)
      + " u32[1]=" + to_string(xt_buf_u32(1) as Int));
    let base = xt_buf_ptr() as Int;
    io.println("base=" + to_string(base));
    let v0 = ffi.ptr_read_u32_le(base as *UInt8);
    let p1 = (base + 4) as *UInt8;
    let v1 = ffi.ptr_read_u32_le(p1);
    io.println("XIOM     u32[0]=" + to_string(v0) + " u32[1]=" + to_string(v1));
    io.flush_stdout();
  }
  return 0;
}
