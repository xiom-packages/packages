// B-23 minimal repro (v0.64.4): the `null` pointer literal does NOT marshal
// to 0 when passed as a C extern argument.  A zero pointer that ORIGINATED
// from C converts correctly, so bridge-provided nulls are the workaround.
//
// Run:
//   . scripts\xiom.ps1
//   $tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
//   & $tool.Xiom --run <abs>\probe.xi --c-source <abs>\host.c
module null_literal_probe

use xiom.io;

extern "C" {
  fn xs_ptr_val(p: *UInt8) -> Int;
  fn xs_null() -> *UInt8;
}

fn get_null() -> *UInt8
  requires: true
{
  unsafe { return xs_null(); }
}

fn forward(p: *UInt8) -> Int
  requires: true
{
  unsafe { return xs_ptr_val(p); }
}

fn probe_direct() -> Int
  requires: true
{
  unsafe { return xs_ptr_val(null); }
}

fn main() -> Int {
  let direct = probe_direct();
  let via_fn = forward(null);
  let c_null = get_null();
  let from_c = unsafe { xs_ptr_val(c_null) as Int };
  let via_var = unsafe { xs_ptr_val(c_null as *UInt8) as Int };
  io.println("direct=" + to_string(direct) + " via_fn=" + to_string(via_fn)
    + " from_c=" + to_string(from_c) + " via_var=" + to_string(via_var));
  var failed = 0;
  if direct != 0 { failed = failed + 1; }
  if via_fn != 0 { failed = failed + 1; }
  if from_c != 0 { failed = failed + 1; }
  if via_var != 0 { failed = failed + 1; }
  return failed;
}
