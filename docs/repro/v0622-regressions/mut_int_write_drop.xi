// v0.62.2 regression repro (MINIMAL): assignment through a `&mut Int`
// parameter is silently dropped.
//
// Expected: `st=99` (and a second run would stay 99).
// Observed on v0.62.2 (installed): `st=10` -- the write never lands.
// Exit code 0, no diagnostics.
//
// Originally found by `xiom.svm`: `_svm_shuffle(order: &mut Vec[Int], state:
// &mut Int)` never advanced `state`, so every seed produced the same shuffle
// and retraining the same seed produced different models. The workaround used
// there (and by all wave-46 packages) is to thread scalar state through the
// return value instead of a `&mut Int` parameter.
//
// The sibling shape `fn bump(s: &mut Int) { let v = byval(s); s = v; }` with
// `fn byval(x: Int) -> Int` also drops the write (observed `st=10, st2=10`
// where 11, 12 were expected), so the essence is the write through the
// `&mut Int` parameter, not the call.
//
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module mut_int_write_drop

use xiom.io;
use xiom.convert;

fn set99(s: &mut Int) { s = 99; }

fn main() -> Int {
  var st: Int = 10;
  set99(&mut st);
  io.println("st=" + int_to_string(st));
  return 0;
}
