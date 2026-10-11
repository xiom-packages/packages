// B-18 repro (regression in compiler commit fde5548e, m263-m265):
// passing a BARE TOP-LEVEL fn NAME as a fn-typed EXTERN parameter makes the
// enclosing function return early with 0 -- silently.
//
// Pre-fix v0.64.3: `fnparam=42` / `after=42` (this shape WORKED; it was the
// control for B-13).  Post-fix (fde5548e): everything before the call runs;
// the call never delivers control back to the NEXT statement -- the
// enclosing function returns 0 immediately (main returned r=0 instead of 7
// in the control-flow arm below), exit code 0, no diagnostic.
//
// Working shapes on the same fix build (do NOT regress these): fn-typed
// PARAM -> extern fn-typed param (probe4 A), local -> extern (probe4 B),
// cast-call with fn-typed param (probe4 C), name `as Int` -> extern Int
// param (probe direct).  Broken shape: NAME -> extern fn-typed param
// (this file, probe3_fnparam.xi, probe6_registry.xi).
//
// Run (from the repo root; absolute paths):
//   . scripts\xiom.ps1
//   $tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
//   & $tool.Xiom --run <abs>\probe8_name_fnparam.xi --c-source <abs>\cbhost.c
//
// Expected on a healthy compiler:
//   before
//   after=42
//   main-before
//   callee-before
//   callee-after=42
//   main-after r=7
// Observed on fde5548e: `before`, then `main-before`, `callee-before`,
// `main-after r=0` (the `after`/`callee-after` lines never print).

module cb_name_fnparam_probe

use xiom.io;
use xiom.convert;

extern "C" {
  fn xt_cb_int_fn(f: fn(Int32) -> Int32, x: Int32) -> Int32;
}

fn cb_double(x: Int32) -> Int32 { return x * 2; }

// Arm 1: the minimal case (was probe8).
fn arm_minimal() {
  io.println("before");
  io.flush_stdout();
  unsafe {
    let r = xt_cb_int_fn(cb_double, 21) as Int;
    io.println("after=" + int_to_string(r));
    io.flush_stdout();
  }
}

// Arm 2: control-flow shape (was probe9) -- does the callee return to the
// caller, and with what value?
fn callit() -> Int {
  io.println("callee-before");
  io.flush_stdout();
  unsafe {
    let r = xt_cb_int_fn(cb_double, 21) as Int;
    io.println("callee-after=" + int_to_string(r));
    io.flush_stdout();
  }
  return 7;
}

fn main() -> Int {
  arm_minimal();
  io.println("main-before");
  io.flush_stdout();
  let r = callit();
  io.println("main-after r=" + int_to_string(r));
  io.flush_stdout();
  return 0;
}
