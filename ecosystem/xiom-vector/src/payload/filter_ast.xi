module xiom.vector.payload.filter_ast

use xiom.vector.payload.payload;

// Filter expression tree evaluated against a point's Payload during search.
// And/Or/Not carry their operands in a Vec: XIOM has no direct self-referential
// enum field, and a Vec supplies the required indirection. SCAFFOLD — the
// constructors are real; evaluation lives in filter_eval (Phase 3).

pub enum FilterExpr {
  Eq(field: Str, value: FieldValue),
  Range(field: Str, lo: Float32, hi: Float32),
  Exists(field: Str),
  In(field: Str, values: Vec[FieldValue]),
  And(clauses: Vec[FilterExpr]),
  Or(clauses: Vec[FilterExpr]),
  Not(clauses: Vec[FilterExpr]),
}

pub fn filter_eq(field: Str, value: FieldValue) -> FilterExpr {
  return FilterExpr.Eq(field, value);
}

pub fn filter_range(field: Str, lo: Float32, hi: Float32) -> FilterExpr {
  return FilterExpr.Range(field, lo, hi);
}

pub fn filter_exists(field: Str) -> FilterExpr {
  return FilterExpr.Exists(field);
}

pub fn filter_in(field: Str, values: Vec[FieldValue]) -> FilterExpr {
  return FilterExpr.In(field, values);
}

pub fn filter_and(clauses: Vec[FilterExpr]) -> FilterExpr {
  return FilterExpr.And(clauses);
}

pub fn filter_or(clauses: Vec[FilterExpr]) -> FilterExpr {
  return FilterExpr.Or(clauses);
}

pub fn filter_not(clause: FilterExpr) -> FilterExpr {
  var clauses = Vec[FilterExpr].new();
  clauses.push(clause);
  return FilterExpr.Not(clauses);
}
