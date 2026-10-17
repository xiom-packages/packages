// C-ORBIT-10 minimal repro (syntax-error path): `xiom --check` must exit
// nonzero when it reports errors. See README for the observed exit codes.
module orbitdb_repro_check_exit_syntax

fn main() -> Int {
  return 0
