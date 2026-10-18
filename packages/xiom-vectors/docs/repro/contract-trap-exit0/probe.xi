// Probe: does execution continue after a `requires` violation, and what is
// the exit code? main returns take_positive(-5): continuation -> 251,
// trap/abort -> some fixed code.
module probe_contract_trap

fn take_positive(x: Int) -> Int
  requires: x > 0
{
  return x;
}

fn main() -> Int {
  return take_positive(-5);
}
