module xiom.vector.payload.filter_eval
// Local inline of payload logic.
use xiom.vector.payload.filter_ast;

pub enum FieldValue {
  IntVal(v: Int),
  FloatVal(v: Float32),
  TextVal(v: Str),
  BoolVal(v: Bool),
}

pub type PayloadField = { key: Str; value: FieldValue; }
pub type Payload = { fields: Vec[PayloadField]; }

fn payload_has(p: &Payload, key: Str) -> Bool {
  var i: Int = 0;
  while i < p.fields.len() {
    if p.fields[i].key == key {
      return true;
    }
    i = i + 1;
  }
  return false;
}

pub fn filter_matches(expr: &FilterExpr, p: &Payload) -> Bool {
  match expr {
    Eq(field, value) => {
      return payload_has(p, field);
    }
    Range(field, lo, hi) => {
      return payload_has(p, field);
    }
    Exists(field) => {
      return payload_has(p, field);
    }
    In(field, values) => {
      return payload_has(p, field);
    }
    And(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if !filter_matches(&clauses[i], p) {
          return false;
        }
        i = i + 1;
      }
      return true;
    }
    Or(clauses) => {
      var i: Int = 0;
      while i < clauses.len() {
        if filter_matches(&clauses[i], p) {
          return true;
        }
        i = i + 1;
      }
      return false;
    }
    Not(clauses) => {
      if clauses.len() == 0 {
        return true;
      }
      return !filter_matches(&clauses[0], p);
    }
  }
}