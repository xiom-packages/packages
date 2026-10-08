// Build+run: xiom --run tests/probe.xi
// Expected on v0.64.0: hangs after "before" (the stdout flush shows how far
// it got); kill with a watchdog. A control without the ffi.free call, or
// with libc malloc/free declared module-locally, exits 0.
module probe_alloc_guard_test

use xiom.io;
use probe_alloc_guard.m;

fn main() -> Int {
  io.println("before");
  io.flush_stdout();
  let v = spin();
  io.println("after v=ok");
  return 0;
}
