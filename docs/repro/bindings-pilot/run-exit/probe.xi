// B-08 run-exit probe: `xiom --run` must surface the program's exit code.
// v0.64.0/v0.64.1: a program returning 5 finished with compiler exit 0 (the
// program's code was masked).  Expected on v0.64.2 (m228): the compiler
// prints "exit code: 5" and itself exits 5.
module run_exit_probe

use xiom.io;

fn main() -> Int {
  io.println("run-exit probe: returning 5");
  io.flush_stdout();
  return 5;
}
