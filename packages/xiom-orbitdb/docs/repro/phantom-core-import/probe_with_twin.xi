// XIOM ORBITDB repro -- case 2: a foreign same-named type in the catalog
// turns the silently-tolerated phantom into a hard T001.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Identical to probe_alone.xi except that `twin.xi` (declaring `CoreError`)
// is reachable via `use twin;`. `xiom --check` now fails with:
//   error[T001]: <line>: match pattern 'Corruption' belongs to 'DbError',
//   not 'CoreError'
// (the scrutinee name resolves to the foreign type while the bare pattern
// resolves to the same-module enum; no ambiguity diagnostic).
//
// This is exactly what happened on v0.64.2 when the ORBITDB + XVECTOR source
// trees were composed (hybrid probe): `xiom.vector.core.shim` declares an
// inline `CoreError` stand-in, which bound the name in `xiom.db.error`.

module orbitdb_repro_phantom_with_twin

use xiom.core.error;
use twin;

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
