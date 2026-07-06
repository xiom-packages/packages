module xiom.vector.payload.filter_eval

use xiom.vector.payload.payload;
use xiom.vector.payload.filter_ast;

// Evaluate a FilterExpr against a Payload. SCAFFOLD: the boolean combinators
// (And/Or/Not) and Exists are fully implemented; the value predicates
// (Eq/Range/In) currently only test for field presence (fail-open) so the
// search path can be wired end-to-end before the typed comparisons land in
// Phase 3.

pub fn filter_matches(expr: &FilterExpr, p: &Payload) -> Bool {
  match expr {
    Eq(field, value) {
      // TODO(Phase 3): resolve `field` in payload and compare against `value`.
      return payload_has(p, field);
    }
    Range(field, lo, hi) {
      // TODO(Phase 3): numeric range check [lo, hi] on the resolved field.
      return payload_has(p, field);
    }
    Exists(field) {
      return payload_has(p, field);
    }
    In(field, values) {
      // TODO(Phase 3): membership test of the field value within `values`.
      return payload_has(p, field);
    }
    And(clauses) {
      var i: Int = 0;
      while i < clauses.len() {
        if !filter_matches(&clauses[i], p) {
          return false;
        }
        i = i + 1;
      }
      return true;
    }
    Or(clauses) {
      var i: Int = 0;
      while i < clauses.len() {
        if filter_matches(&clauses[i], p) {
          return true;
        }
        i = i + 1;
      }
      return false;
    }
    Not(clauses) {
      if clauses.len() == 0 {
        return true;
      }
      return !filter_matches(&clauses[0], p);
    }
  }
}
