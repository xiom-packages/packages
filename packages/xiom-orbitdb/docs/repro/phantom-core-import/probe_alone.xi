// XIOM ORBITDB repro -- unresolved `use` + undeclared type in a signature is
// silently accepted (no diagnostic beyond bogus W004 unreachable arms).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The module `xiom.core.error` does not exist in the stdlib (nor in any
// installed package), so `CoreError` is an undeclared type used only in a
// signature and as a match scrutinee. `xiom --check` reports two W004
// "unreachable match arm" warnings (the bare variants resolve to the
// same-module `DbError`, which is not the scrutinee) and then PASSES.
// This is the state src/error.xi was in (the fold was dead code for months).
//
// Case 2 (probe_with_twin.xi) shows the hard failure once ANY module in the
// program declares a type with the same name: the name binds across modules
// and the same match arm becomes a hard T001.

module orbitdb_repro_phantom_alone

use xiom.core.error;

pub enum DbError {
  NotFound,
  Corruption,
}

pub fn fold(e: &CoreError) -> DbError {
  match e {
    NotFound => DbError.NotFound,
    Corruption(_) => DbError.Corruption,
    _ => DbError.NotFound,
  }
}
