// XIOM -- probe: Result[Str, enum-with-Str] payload in Vec (v0.64.8)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Minimal reduction of the defects observed while testing xiom.jev.batch.
// One enum with a Str payload and built-in Result are enough; no package
// import is needed.
//
// OBSERVED on compiler v0.64.8 (Windows x64):
//   A. v.push(Err(E.Bad("direct"))) drops the Err Str payload: reading the
//      element back yields the E.Bad tag with an EMPTY reason. Other
//      interleaved push patterns can also perturb element order.
//   B. Building the same Result in a helper, binding it to a local, and
//      pushing that local (`let r = err("via"); v.push(r);`) keeps both
//      order and the exact reason.
//   C. Returning the Vec from a helper is not itself the problem when the
//      elements were pushed from locals (see the "returned" control).
//
// Expected output: direct=direct, via=via, returned=returned.
// Observed output: direct=, via=via, returned=returned.
//
// Workaround used by xiom.jev.batch tests: bind each Result to a local
// before pushing (the mixed fixtures do this). batch_collect itself takes
// &Vec and is not the source of the loss.

module batch_result_vec_push

use xiom.io;

pub enum E {
  Bad(reason: Str),
}

fn err(reason: Str) -> Result[Str, E] {
  return Err(E.Bad(reason));
}

// e_text takes the ENUM by value, not a Result; that path is correct.
fn e_text(e: E) -> Str {
  match e {
    E.Bad(reason) => { return reason; },
  };
}

fn read_reason(r: Result[Str, E]) -> Str {
  let e: E = r.error;
  return e_text(e);
}

fn probe_direct_push() -> Int {
  var v: Vec[Result[Str, E]] = Vec[Result[Str, E]].new();
  v.push(Err(E.Bad("direct")));
  let r: Result[Str, E] = v[0];
  io.println("direct=" + read_reason(r));
  return 0;
}

fn probe_local_push() -> Int {
  var v: Vec[Result[Str, E]] = Vec[Result[Str, E]].new();
  let r0: Result[Str, E] = err("via");
  v.push(r0);
  let r: Result[Str, E] = v[0];
  io.println("via=" + read_reason(r));
  return 0;
}

fn build_vec() -> Vec[Result[Str, E]] {
  var v: Vec[Result[Str, E]] = Vec[Result[Str, E]].new();
  let r0: Result[Str, E] = err("returned");
  v.push(r0);
  return v;
}

fn probe_return_boundary() -> Int {
  let v: Vec[Result[Str, E]] = build_vec();
  let r: Result[Str, E] = v[0];
  io.println("returned=" + read_reason(r));
  return 0;
}

fn main() -> Int {
  probe_direct_push();
  probe_local_push();
  probe_return_boundary();
  return 0;
}
