// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module xiom.vector.payload.filter_eval

// Typed filter evaluation against a Payload (and against a PayloadStore for
// the engine's per-candidate check). Extracted from the consolidated engine.
//
// Semantics: value predicates on a missing field are false; boolean
// combinators keep their structure with the empty semantics:
// And([]) = true, Or([]) = false, Not([]) = true.

use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;

// Evaluate a filter against one payload.
pub fn filter_matches(expr: &FilterExpr, p: &Payload) -> Bool {
  match expr {
    Eq(field, value) => {
      match payload_get(p, field) {
        Some(fv) => { return field_value_eq(&fv, &value); }
        None => { return false; }
      }
    }
    Range(field, lo, hi) => {
      match payload_get(p, field) {
        Some(fv) => {
          match field_value_as_float(&fv) {
            Some(f) => { return f >= lo && f <= hi; }
            None => { return false; }
          }
        }
        None => { return false; }
      }
    }
    Exists(field) => { return payload_has(p, field); }
    In(field, values) => {
      match payload_get(p, field) {
        Some(fv) => {
          var i: Int = 0;
          while i < values.len() {
            if field_value_eq(&fv, &values[i]) { return true; }
            i = i + 1;
          }
          return false;
        }
        None => { return false; }
      }
    }
    And(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if !filter_matches(&clauses[i], p) { return false; }
        i = i + 1;
      }
      return true;
    }
    Or(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if filter_matches(&clauses[i], p) { return true; }
        i = i + 1;
      }
      return false;
    }
    Not(clauses) => {
      if clauses.len() == 0 { return true; }
      return !filter_matches(&clauses[0], p);
    }
  }
}

// Same boolean structure as filter_matches but for a point with NO payload:
// every value predicate is false; combinators compose (And([]) = true etc.).
fn filter_matches_empty(expr: &FilterExpr) -> Bool {
  match expr {
    And(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if !filter_matches_empty(&clauses[i]) { return false; }
        i = i + 1;
      }
      return true;
    }
    Or(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if filter_matches_empty(&clauses[i]) { return true; }
        i = i + 1;
      }
      return false;
    }
    Not(clauses) => {
      if clauses.len() == 0 { return true; }
      return !filter_matches_empty(&clauses[0]);
    }
    _ => { return false; }
  }
}

// Filter check for a point id: uses its payload when present, otherwise the
// empty-payload semantics.
pub fn payload_store_matches(s: &PayloadStore, id: Int, expr: &FilterExpr) -> Bool {
  var i: Int = 0;
  while i < s.entries.len() {
    if s.entries[i].id == id {
      return filter_matches(expr, &s.entries[i].payload);
    }
    i = i + 1;
  }
  return filter_matches_empty(expr);
}
