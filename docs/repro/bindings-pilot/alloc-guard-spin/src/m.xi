// Compiler probe: stdlib ffi.alloc inside a confined block, freed through
// ffi.free. On v0.64.0 the guard pass rewrites the alloc to
// xiom_guard_alloc inside the block while ffi.free still calls libc free;
// the guard heap then spins (flat memory, ~100% CPU, no output).
//
// ALWAYS run under a memory/time watchdog:
//   powershell -File watch.ps1 -Exe .\probe.exe -MemMB 512 -TimeoutSec 10
module probe_alloc_guard.m

use xiom.ffi;

pub fn spin() -> Int
  requires: true
{
  unsafe {
    let slot = ffi.alloc(8);
    ffi.ptr_write_u64_le(slot, 4242);
    let v = ffi.ptr_read_u64_le(slot);
    ffi.free(slot);
    return v;
  }
}
