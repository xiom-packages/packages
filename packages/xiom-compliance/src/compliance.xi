// XIOM -- xiom.compliance: deterministic compliance rule engine with typed
// evidence attributes, expiring waivers, severity rollup and a canonical
// findings report
// Port task: replace the xiom.compliance placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Contract (see SPEC.md for the full definition):
//   - a RuleSet is nine index-aligned parallel vectors, one slot per rule;
//     rule i is (ids[i], severities[i], subjects[i], attrs[i], ops[i],
//     int_a[i], int_b[i], strs[i], enabled[i]);
//   - an Evidence record is four index-aligned parallel vectors: names[i],
//     kinds[i] and the typed value in ints[i] (CMPL_INT) or strs[i] (CMPL_STR);
//     attribute lookup is first-match by byte-exact name;
//   - a waiver entry i is active at tick `now` when expiry_ticks[i] > now, so
//     a waiver expires AT its expiry tick; a failing rule with an active
//     waiver for its id produces CMPL_WAIVED instead of CMPL_VIOLATION;
//   - every rule gets exactly one outcome: CMPL_PASS, CMPL_VIOLATION,
//     CMPL_WAIVED or CMPL_NOT_APPLICABLE (disabled rule, attribute missing
//     from the evidence, or attribute kind mismatch);
//   - severity weights are powers of two (1, 2, 4, 8, 16); the risk score
//     sums violations only, the waived score sums waived findings only.
//
// Vec[StructType] is unsupported in this compiler, so every record is flat.
// Free functions only; Str equality goes through xiom.string.str_compare
// (BUG 17: `==` on Str values read from Vec[Str] elements lowers to a pointer
// comparison). No floats and no clocks: `now` is a caller-supplied Int tick.

module xiom.compliance

use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  Predicate subject kinds
// --------------------------------------------------

/// Subject kind: the predicate reads an integer attribute.
pub const CMPL_INT: Int = 0;
/// Subject kind: the predicate reads a string attribute.
pub const CMPL_STR: Int = 1;

// --------------------------------------------------
//  Integer predicate operators
// --------------------------------------------------

/// Integer op: `value == int_a[i]`.
pub const CMPL_OP_INT_EQ: Int = 0;
/// Integer op: `value != int_a[i]`.
pub const CMPL_OP_INT_NEQ: Int = 1;
/// Integer op: `int_a[i] <= value <= int_b[i]` (inclusive on both ends).
pub const CMPL_OP_INT_RANGE: Int = 2;

// --------------------------------------------------
//  String predicate operators
// --------------------------------------------------

/// String op: byte-exact `value == strs[i]`.
pub const CMPL_OP_STR_EQ: Int = 0;
/// String op: byte-exact `value != strs[i]`.
pub const CMPL_OP_STR_NEQ: Int = 1;
/// String op: `value` starts with `strs[i]`.
pub const CMPL_OP_STR_PREFIX: Int = 2;
/// String op: `value` contains `strs[i]`.
pub const CMPL_OP_STR_CONTAINS: Int = 3;

// --------------------------------------------------
//  Finding outcomes
// --------------------------------------------------

/// Outcome: the rule is enabled and its predicate is satisfied.
pub const CMPL_PASS: Int = 0;
/// Outcome: the rule is enabled, its predicate is not satisfied and no
/// active waiver covers it.
pub const CMPL_VIOLATION: Int = 1;
/// Outcome: the rule failed but an active waiver for its id covers it.
pub const CMPL_WAIVED: Int = 2;
/// Outcome: disabled rule, attribute missing from the evidence, or the
/// attribute kind does not match the rule's subject kind.
pub const CMPL_NOT_APPLICABLE: Int = 3;

// --------------------------------------------------
//  Severity scale
// --------------------------------------------------

/// Severity: informational.
pub const CMPL_SEV_INFO: Int = 0;
/// Severity: low.
pub const CMPL_SEV_LOW: Int = 1;
/// Severity: medium.
pub const CMPL_SEV_MEDIUM: Int = 2;
/// Severity: high.
pub const CMPL_SEV_HIGH: Int = 3;
/// Severity: critical.
pub const CMPL_SEV_CRITICAL: Int = 4;

// --------------------------------------------------
//  Rule set
// --------------------------------------------------

/// Compliance rule set: nine index-aligned parallel vectors, one slot per
/// rule. `subjects[i]` is CMPL_INT or CMPL_STR and selects which predicate
/// family `ops[i]` belongs to and which typed operand vector is read
/// (`int_a`/`int_b` for integers, `strs` for strings). `enabled[i]` is 1 or 0;
/// a disabled rule always evaluates to CMPL_NOT_APPLICABLE. Construct through
/// cmpl_rules_new and mutate through cmpl_rule_int / cmpl_rule_str /
/// cmpl_rule_set_enabled: every operation keeps all nine vectors the same
/// length. Evaluation additionally guards against drift by using the shortest
/// vector as the rule count.
pub type RuleSet = {
  ids: Vec[Str];
  severities: Vec[Int];
  subjects: Vec[Int];
  attrs: Vec[Str];
  ops: Vec[Int];
  int_a: Vec[Int];
  int_b: Vec[Int];
  strs: Vec[Str];
  enabled: Vec[Int];
}

// --------------------------------------------------
//  Evidence
// --------------------------------------------------

/// Evidence attribute map as four index-aligned parallel vectors: entry i is
/// named names[i], has kind kinds[i] (CMPL_INT or CMPL_STR) and carries its
/// value in ints[i] or strs[i] correspondingly. The unused typed vector holds
/// 0 / "" for that entry. Lookup (cmpl_evidence_has, _cmpl_attr_index) is
/// first-match by byte-exact name; duplicates are kept, never collapsed.
/// Construct through cmpl_evidence_new and mutate through
/// cmpl_evidence_put_int / cmpl_evidence_put_str.
pub type Evidence = {
  names: Vec[Str];
  kinds: Vec[Int];
  ints: Vec[Int];
  strs: Vec[Str];
}

// --------------------------------------------------
//  Waivers
// --------------------------------------------------

/// Waiver list as two index-aligned parallel vectors: entry i waives every
/// finding of rule rule_ids[i] while the evaluation tick `now` is strictly
/// below expiry_ticks[i]. Construct through cmpl_waivers_new and mutate
/// through cmpl_waive. Multiple waivers for the same rule id are allowed; the
/// rule is waived when any of them is active.
pub type WaiverSet = {
  rule_ids: Vec[Str];
  expiry_ticks: Vec[Int];
}

// --------------------------------------------------
//  Findings
// --------------------------------------------------

/// Evaluation result: one finding per evaluated rule, in rule order, as four
/// index-aligned parallel vectors. `details[i]` is the examined attribute
/// name, or "" for a disabled rule. Built only by cmpl_eval, which keeps the
/// vectors aligned.
pub type Findings = {
  rule_ids: Vec[Str];
  severities: Vec[Int];
  outcomes: Vec[Int];
  details: Vec[Str];
}

// --------------------------------------------------
//  Internal helpers
// --------------------------------------------------

// Byte-exact Str equality (BUG 17-safe: never `==` on Str values).
fn _cmpl_streq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn _cmpl_min(a: Int, b: Int) -> Int {
  if a < b {
    return a;
  }
  return b;
}

// Rule count guard: the shortest of the nine parallel vectors. Keeps every
// loop bounded even if a caller hand-drifts the record (trap: parallel Vecs).
fn _cmpl_rules_n(s: &RuleSet) -> Int {
  var n = s.ids.len();
  n = _cmpl_min(n, s.severities.len());
  n = _cmpl_min(n, s.subjects.len());
  n = _cmpl_min(n, s.attrs.len());
  n = _cmpl_min(n, s.ops.len());
  n = _cmpl_min(n, s.int_a.len());
  n = _cmpl_min(n, s.int_b.len());
  n = _cmpl_min(n, s.strs.len());
  n = _cmpl_min(n, s.enabled.len());
  return n;
}

fn _cmpl_evidence_n(e: &Evidence) -> Int {
  var n = e.names.len();
  n = _cmpl_min(n, e.kinds.len());
  n = _cmpl_min(n, e.ints.len());
  n = _cmpl_min(n, e.strs.len());
  return n;
}

fn _cmpl_waivers_n(w: &WaiverSet) -> Int {
  return _cmpl_min(w.rule_ids.len(), w.expiry_ticks.len());
}

fn _cmpl_findings_n(f: &Findings) -> Int {
  var n = f.rule_ids.len();
  n = _cmpl_min(n, f.severities.len());
  n = _cmpl_min(n, f.outcomes.len());
  n = _cmpl_min(n, f.details.len());
  return n;
}

// First index in the evidence whose name equals `name`, or -1. Linear
// first-match; duplicates keep their first position.
fn _cmpl_attr_index(e: &Evidence, name: Str) -> Int {
  let n = _cmpl_evidence_n(e);
  var i = 0;
  while i < n {
    let candidate: Str = e.names[i];
    if _cmpl_streq(candidate, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Predicates
// --------------------------------------------------

/// Integer predicate. `op` is one of CMPL_OP_INT_EQ (`value == a`),
/// CMPL_OP_INT_NEQ (`value != a`) or CMPL_OP_INT_RANGE (`a <= value <= b`,
/// inclusive). An unknown op returns false (never an error). `b` is ignored
/// by EQ/NEQ.
/// Params: op - operator code; a - equality operand or range lower bound;
///         b - range upper bound; value - the attribute value.
/// Returns: the predicate truth value. Error case: none. Complexity: O(1).
pub fn cmpl_pred_int(op: Int, a: Int, b: Int, value: Int) -> Bool {
  if op == CMPL_OP_INT_EQ {
    return value == a;
  }
  if op == CMPL_OP_INT_NEQ {
    return value != a;
  }
  if op == CMPL_OP_INT_RANGE {
    return value >= a && value <= b;
  }
  return false;
}

/// String predicate. `op` is one of CMPL_OP_STR_EQ / CMPL_OP_STR_NEQ
/// (byte-exact via str_compare), CMPL_OP_STR_PREFIX (`value` starts with
/// `operand`) or CMPL_OP_STR_CONTAINS (`value` contains `operand`). An empty
/// operand is handled directly (no stdlib call, avoiding the
/// xiom.string.index_of `substr.len() > 0` contract): PREFIX and CONTAINS are
/// true for every value, EQ is true only for an empty value. An unknown op
/// returns false (never an error).
/// Params: op - operator code; operand - the pattern/value to compare against;
///         value - the attribute value.
/// Returns: the predicate truth value. Error case: none. Complexity: O(len).
pub fn cmpl_pred_str(op: Int, operand: Str, value: Str) -> Bool {
  if operand.len() == 0 {
    if op == CMPL_OP_STR_EQ {
      return value.len() == 0;
    }
    if op == CMPL_OP_STR_NEQ {
      return value.len() != 0;
    }
    if op == CMPL_OP_STR_PREFIX {
      return true;
    }
    if op == CMPL_OP_STR_CONTAINS {
      return true;
    }
    return false;
  }
  if op == CMPL_OP_STR_EQ {
    return _cmpl_streq(operand, value);
  }
  if op == CMPL_OP_STR_NEQ {
    return !_cmpl_streq(operand, value);
  }
  if op == CMPL_OP_STR_PREFIX {
    return string.str_starts_with(value, operand);
  }
  if op == CMPL_OP_STR_CONTAINS {
    return string.str_contains(value, operand);
  }
  return false;
}

// --------------------------------------------------
//  Rule set construction
// --------------------------------------------------

/// Fresh empty rule set: no rules, so evaluation yields no findings.
/// Returns: a RuleSet with nine empty parallel vectors.
/// Error case: none. Complexity: O(1).
pub fn cmpl_rules_new() -> RuleSet {
  return RuleSet{
    ids: Vec[Str].new();
    severities: Vec[Int].new();
    subjects: Vec[Int].new();
    attrs: Vec[Str].new();
    ops: Vec[Int].new();
    int_a: Vec[Int].new();
    int_b: Vec[Int].new();
    strs: Vec[Str].new();
    enabled: Vec[Int].new();
  };
}

// Append one fully-specified rule slot; all nine vectors grow together.
fn _cmpl_rule_push(s: &mut RuleSet, id: Str, severity: Int, subject: Int, attr: Str, op: Int, a: Int, b: Int, operand: Str) {
  s.ids.push(id);
  s.severities.push(severity);
  s.subjects.push(subject);
  s.attrs.push(attr);
  s.ops.push(op);
  s.int_a.push(a);
  s.int_b.push(b);
  s.strs.push(operand);
  s.enabled.push(1);
}

/// Append an integer-attribute rule and enable it.
/// Params: s - the rule set to mutate; id - finding id (opaque, may repeat);
///         severity - severity code (any Int; 0..4 are named);
///         attr - evidence attribute name to read; op - CMPL_OP_INT_*;
///         a - equality operand or range lower bound; b - range upper bound.
/// Returns: the index of the new rule (rule count - 1).
/// Error case: none. Complexity: O(1) amortized.
pub fn cmpl_rule_int(s: &mut RuleSet, id: Str, severity: Int, attr: Str, op: Int, a: Int, b: Int) -> Int {
  _cmpl_rule_push(s, id, severity, CMPL_INT, attr, op, a, b, "");
  return s.ids.len() - 1;
}

/// Append a string-attribute rule and enable it.
/// Params: s - the rule set to mutate; id - finding id (opaque, may repeat);
///         severity - severity code (any Int; 0..4 are named);
///         attr - evidence attribute name to read; op - CMPL_OP_STR_*;
///         operand - the eq/neq/prefix/contains operand.
/// Returns: the index of the new rule (rule count - 1).
/// Error case: none. Complexity: O(1) amortized.
pub fn cmpl_rule_str(s: &mut RuleSet, id: Str, severity: Int, attr: Str, op: Int, operand: Str) -> Int {
  _cmpl_rule_push(s, id, severity, CMPL_STR, attr, op, 0, 0, operand);
  return s.ids.len() - 1;
}

/// Number of rules: the shortest of the nine parallel vectors (guards drift).
/// Params: s - the rule set.
/// Returns: the rule count. Error case: none. Complexity: O(1).
pub fn cmpl_rule_count(s: &RuleSet) -> Int {
  return _cmpl_rules_n(s);
}

/// Rule id at index `i`, or "" when `i` is negative or >= cmpl_rule_count.
/// Params: s - the rule set; i - zero-based rule index.
/// Returns: the id, or "" out of range. Error case: none. Complexity: O(1).
pub fn cmpl_rule_id(s: &RuleSet, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= _cmpl_rules_n(s) {
    return "";
  }
  let out: Str = s.ids[i];
  return out;
}

/// Rule severity at index `i`, or -1 when `i` is negative or out of range.
/// Params: s - the rule set; i - zero-based rule index.
/// Returns: the severity code, or -1 out of range.
/// Error case: none. Complexity: O(1).
pub fn cmpl_rule_severity(s: &RuleSet, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= _cmpl_rules_n(s) {
    return -1;
  }
  let out: Int = s.severities[i];
  return out;
}

/// Rule subject kind at index `i`: CMPL_INT or CMPL_STR, or -1 out of range.
/// Params: s - the rule set; i - zero-based rule index.
/// Returns: the subject kind, or -1 out of range.
/// Error case: none. Complexity: O(1).
pub fn cmpl_rule_subject(s: &RuleSet, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= _cmpl_rules_n(s) {
    return -1;
  }
  let out: Int = s.subjects[i];
  return out;
}

/// True when rule `i` is enabled; false for a disabled rule or out-of-range i.
/// Params: s - the rule set; i - zero-based rule index.
/// Returns: enabled state. Error case: none. Complexity: O(1).
pub fn cmpl_rule_is_enabled(s: &RuleSet, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  if i >= _cmpl_rules_n(s) {
    return false;
  }
  let on: Int = s.enabled[i];
  return on != 0;
}

/// Enable or disable rule `i`. Rewrites only `enabled[i]`, so the rule keeps
/// its predicate and no vector is reordered.
/// Params: s - the rule set to mutate; i - zero-based rule index;
///         on - true to enable, false to disable.
/// Returns: true when the index was valid and the flag was written, false
/// for an out-of-range index (a no-op).
/// Error case: none. Complexity: O(1).
pub fn cmpl_rule_set_enabled(s: &mut RuleSet, i: Int, on: Bool) -> Bool {
  if i < 0 {
    return false;
  }
  if i >= _cmpl_rules_n(s) {
    return false;
  }
  if on {
    s.enabled[i] = 1;
  } else {
    s.enabled[i] = 0;
  }
  return true;
}

// --------------------------------------------------
//  Evidence construction
// --------------------------------------------------

/// Fresh empty evidence record: no attributes.
/// Returns: an Evidence with four empty parallel vectors.
/// Error case: none. Complexity: O(1).
pub fn cmpl_evidence_new() -> Evidence {
  return Evidence{
    names: Vec[Str].new();
    kinds: Vec[Int].new();
    ints: Vec[Int].new();
    strs: Vec[Str].new();
  };
}

/// Append an integer attribute. Duplicate names are kept; lookups return the
/// first entry with the name.
/// Params: e - the evidence to mutate; name - attribute name;
///         value - the integer value.
/// Returns: the index of the new entry (count - 1).
/// Error case: none. Complexity: O(1) amortized.
pub fn cmpl_evidence_put_int(e: &mut Evidence, name: Str, value: Int) -> Int {
  e.names.push(name);
  e.kinds.push(CMPL_INT);
  e.ints.push(value);
  e.strs.push("");
  return e.names.len() - 1;
}

/// Append a string attribute. Duplicate names are kept; lookups return the
/// first entry with the name.
/// Params: e - the evidence to mutate; name - attribute name;
///         value - the string value.
/// Returns: the index of the new entry (count - 1).
/// Error case: none. Complexity: O(1) amortized.
pub fn cmpl_evidence_put_str(e: &mut Evidence, name: Str, value: Str) -> Int {
  e.names.push(name);
  e.kinds.push(CMPL_STR);
  e.ints.push(0);
  e.strs.push(value);
  return e.names.len() - 1;
}

/// Number of evidence attributes: the shortest of the four parallel vectors.
/// Params: e - the evidence.
/// Returns: the attribute count. Error case: none. Complexity: O(1).
pub fn cmpl_evidence_count(e: &Evidence) -> Int {
  return _cmpl_evidence_n(e);
}

/// True when an attribute named `name` exists (byte-exact, first-match).
/// Params: e - the evidence; name - attribute name.
/// Returns: presence. Error case: none. Complexity: O(attr count).
pub fn cmpl_evidence_has(e: &Evidence, name: Str) -> Bool {
  return _cmpl_attr_index(e, name) >= 0;
}

/// Kind of the first attribute named `name`: CMPL_INT, CMPL_STR, or -1 when
/// no such attribute exists.
/// Params: e - the evidence; name - attribute name.
/// Returns: the kind, or -1 when absent.
/// Error case: none. Complexity: O(attr count).
pub fn cmpl_evidence_kind(e: &Evidence, name: Str) -> Int {
  let at = _cmpl_attr_index(e, name);
  if at < 0 {
    return -1;
  }
  let k: Int = e.kinds[at];
  if k == CMPL_INT {
    return CMPL_INT;
  }
  if k == CMPL_STR {
    return CMPL_STR;
  }
  return -1;
}

/// Integer value of the first attribute named `name`, or `fallback` when the
/// attribute is absent or is not an integer attribute.
/// Params: e - the evidence; name - attribute name;
///         fallback - value returned when missing or of the wrong kind.
/// Returns: the value or the fallback.
/// Error case: none. Complexity: O(attr count).
pub fn cmpl_evidence_int(e: &Evidence, name: Str, fallback: Int) -> Int {
  let at = _cmpl_attr_index(e, name);
  if at < 0 {
    return fallback;
  }
  let k: Int = e.kinds[at];
  if k != CMPL_INT {
    return fallback;
  }
  let v: Int = e.ints[at];
  return v;
}

/// String value of the first attribute named `name`, or `fallback` when the
/// attribute is absent or is not a string attribute.
/// Params: e - the evidence; name - attribute name;
///         fallback - value returned when missing or of the wrong kind.
/// Returns: the value or the fallback.
/// Error case: none. Complexity: O(attr count).
pub fn cmpl_evidence_str(e: &Evidence, name: Str, fallback: Str) -> Str {
  let at = _cmpl_attr_index(e, name);
  if at < 0 {
    return fallback;
  }
  let k: Int = e.kinds[at];
  if k != CMPL_STR {
    return fallback;
  }
  let v: Str = e.strs[at];
  return v;
}

// --------------------------------------------------
//  Waivers
// --------------------------------------------------

/// Fresh empty waiver set: nothing is waived.
/// Returns: a WaiverSet with two empty parallel vectors.
/// Error case: none. Complexity: O(1).
pub fn cmpl_waivers_new() -> WaiverSet {
  return WaiverSet{
    rule_ids: Vec[Str].new();
    expiry_ticks: Vec[Int].new();
  };
}

/// Append a waiver: findings of `rule_id` are waived while the evaluation
/// tick is strictly below `expiry_tick`. The waiver is appended verbatim,
/// duplicates included.
/// Params: w - the waiver set to mutate; rule_id - the covered rule id;
///         expiry_tick - the tick at which the waiver expires (exclusive).
/// Returns: the index of the new entry (count - 1).
/// Error case: none. Complexity: O(1) amortized.
pub fn cmpl_waive(w: &mut WaiverSet, rule_id: Str, expiry_tick: Int) -> Int {
  w.rule_ids.push(rule_id);
  w.expiry_ticks.push(expiry_tick);
  return w.rule_ids.len() - 1;
}

/// Number of waiver entries: the shortest of the two parallel vectors.
/// Params: w - the waiver set.
/// Returns: the entry count. Error case: none. Complexity: O(1).
pub fn cmpl_waiver_count(w: &WaiverSet) -> Int {
  return _cmpl_waivers_n(w);
}

/// True when at least one waiver for `rule_id` is active at tick `now`, i.e.
/// some entry with that id has expiry_ticks[i] > now. An entry with
/// expiry_ticks[i] == now is already expired (exclusive expiry).
/// Params: w - the waiver set; rule_id - the rule id to look up;
///         now - the evaluation tick.
/// Returns: true when any matching waiver is active.
/// Error case: none. Complexity: O(waiver count).
pub fn cmpl_waiver_active(w: &WaiverSet, rule_id: Str, now: Int) -> Bool {
  let n = _cmpl_waivers_n(w);
  var i = 0;
  while i < n {
    let rid: Str = w.rule_ids[i];
    if _cmpl_streq(rid, rule_id) {
      let exp: Int = w.expiry_ticks[i];
      if now < exp {
        return true;
      }
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Evaluation
// --------------------------------------------------

/// Evaluate every rule against the evidence at tick `now`, producing one
/// finding per rule in rule order:
///   - disabled rule (enabled[i] == 0) -> CMPL_NOT_APPLICABLE, detail "";
///   - attribute absent from the evidence -> CMPL_NOT_APPLICABLE, detail attr;
///   - attribute kind != subjects[i] -> CMPL_NOT_APPLICABLE, detail attr;
///   - predicate true -> CMPL_PASS, detail attr;
///   - predicate false, active waiver for ids[i] -> CMPL_WAIVED, detail attr;
///   - predicate false, no active waiver -> CMPL_VIOLATION, detail attr.
/// Evaluation reads only the shortest prefix where all nine rule vectors are
/// present; the result does not depend on evaluation order.
/// Params: s - the rule set; e - the evidence; w - the waiver set;
///         now - the evaluation tick.
/// Returns: a Findings record with four aligned parallel vectors.
/// Error case: none. Complexity: O(rule count * (attr count + ...)).
pub fn cmpl_eval(s: &RuleSet, e: &Evidence, w: &WaiverSet, now: Int) -> Findings {
  var out = Findings{
    rule_ids: Vec[Str].new();
    severities: Vec[Int].new();
    outcomes: Vec[Int].new();
    details: Vec[Str].new();
  };
  let n = _cmpl_rules_n(s);
  var i = 0;
  while i < n {
    let id: Str = s.ids[i];
    let sev: Int = s.severities[i];
    let attr: Str = s.attrs[i];
    let on: Int = s.enabled[i];
    var outcome = CMPL_NOT_APPLICABLE;
    var detail = "";
    if on == 0 {
      outcome = CMPL_NOT_APPLICABLE;
      detail = "";
    } else {
      let at = _cmpl_attr_index(e, attr);
      if at < 0 {
        outcome = CMPL_NOT_APPLICABLE;
        detail = attr;
      } else {
        let kind: Int = e.kinds[at];
        let want: Int = s.subjects[i];
        if kind != want {
          outcome = CMPL_NOT_APPLICABLE;
          detail = attr;
        } else {
          var sat = false;
          if want == CMPL_INT {
            let v: Int = e.ints[at];
            let op: Int = s.ops[i];
            let a: Int = s.int_a[i];
            let b: Int = s.int_b[i];
            sat = cmpl_pred_int(op, a, b, v);
          } else {
            let v: Str = e.strs[at];
            let op2: Int = s.ops[i];
            let p: Str = s.strs[i];
            sat = cmpl_pred_str(op2, p, v);
          }
          detail = attr;
          if sat {
            outcome = CMPL_PASS;
          } else {
            if cmpl_waiver_active(w, id, now) {
              outcome = CMPL_WAIVED;
            } else {
              outcome = CMPL_VIOLATION;
            }
          }
        }
      }
    }
    out.rule_ids.push(id);
    out.severities.push(sev);
    out.outcomes.push(outcome);
    out.details.push(detail);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Findings access and aggregation
// --------------------------------------------------

/// Number of findings: the shortest of the four parallel vectors.
/// Params: f - the findings.
/// Returns: the finding count. Error case: none. Complexity: O(1).
pub fn cmpl_findings_len(f: &Findings) -> Int {
  return _cmpl_findings_n(f);
}

/// Rule id of finding `i`, or "" when `i` is negative or out of range.
/// Params: f - the findings; i - zero-based finding index.
/// Returns: the rule id, or "". Error case: none. Complexity: O(1).
pub fn cmpl_finding_rule(f: &Findings, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= _cmpl_findings_n(f) {
    return "";
  }
  let out: Str = f.rule_ids[i];
  return out;
}

/// Severity of finding `i`, or -1 when `i` is negative or out of range.
/// Params: f - the findings; i - zero-based finding index.
/// Returns: the severity code, or -1. Error case: none. Complexity: O(1).
pub fn cmpl_finding_severity(f: &Findings, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= _cmpl_findings_n(f) {
    return -1;
  }
  let out: Int = f.severities[i];
  return out;
}

/// Outcome of finding `i` (CMPL_PASS / CMPL_VIOLATION / CMPL_WAIVED /
/// CMPL_NOT_APPLICABLE), or -1 when `i` is negative or out of range.
/// Params: f - the findings; i - zero-based finding index.
/// Returns: the outcome code, or -1. Error case: none. Complexity: O(1).
pub fn cmpl_finding_outcome(f: &Findings, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= _cmpl_findings_n(f) {
    return -1;
  }
  let out: Int = f.outcomes[i];
  return out;
}

/// Detail of finding `i` (the examined attribute name, "" for a disabled
/// rule), or "" when `i` is negative or out of range.
/// Params: f - the findings; i - zero-based finding index.
/// Returns: the detail, or "". Error case: none. Complexity: O(1).
pub fn cmpl_finding_detail(f: &Findings, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= _cmpl_findings_n(f) {
    return "";
  }
  let out: Str = f.details[i];
  return out;
}

/// Number of findings with outcome `outcome`. An unknown outcome code yields
/// 0. Params: f - the findings; outcome - CMPL_* outcome code.
/// Returns: the count. Error case: none. Complexity: O(finding count).
pub fn cmpl_count(f: &Findings, outcome: Int) -> Int {
  let n = _cmpl_findings_n(f);
  var total = 0;
  var i = 0;
  while i < n {
    let oc: Int = f.outcomes[i];
    if oc == outcome {
      total = total + 1;
    }
    i = i + 1;
  }
  return total;
}

/// Number of findings with both outcome `outcome` and severity `severity`.
/// Params: f - the findings; outcome - CMPL_* outcome code;
///         severity - severity code (0..4 named, any Int accepted).
/// Returns: the count. Error case: none. Complexity: O(finding count).
pub fn cmpl_severity_count(f: &Findings, outcome: Int, severity: Int) -> Int {
  let n = _cmpl_findings_n(f);
  var total = 0;
  var i = 0;
  while i < n {
    let oc: Int = f.outcomes[i];
    let sv: Int = f.severities[i];
    if oc == outcome && sv == severity {
      total = total + 1;
    }
    i = i + 1;
  }
  return total;
}

/// True when the findings contain no CMPL_VIOLATION. Waived findings and
/// not-applicable findings do not affect compliance.
/// Params: f - the findings.
/// Returns: true when violations == 0. Error case: none. Complexity: O(n).
pub fn cmpl_is_compliant(f: &Findings) -> Bool {
  return cmpl_count(f, CMPL_VIOLATION) == 0;
}

/// Severity weight: INFO 1, LOW 2, MEDIUM 4, HIGH 8, CRITICAL 16; any other
/// severity code weighs 0 (it is still reported, as "other").
/// Params: severity - severity code.
/// Returns: the weight. Error case: none. Complexity: O(1).
pub fn cmpl_severity_weight(severity: Int) -> Int {
  if severity == CMPL_SEV_INFO {
    return 1;
  }
  if severity == CMPL_SEV_LOW {
    return 2;
  }
  if severity == CMPL_SEV_MEDIUM {
    return 4;
  }
  if severity == CMPL_SEV_HIGH {
    return 8;
  }
  if severity == CMPL_SEV_CRITICAL {
    return 16;
  }
  return 0;
}

/// Risk score: the sum of cmpl_severity_weight over CMPL_VIOLATION findings
/// only. Waived findings are excluded (see cmpl_waived_score).
/// Params: f - the findings.
/// Returns: the non-negative score. Error case: none. Complexity: O(n).
pub fn cmpl_risk_score(f: &Findings) -> Int {
  let n = _cmpl_findings_n(f);
  var total = 0;
  var i = 0;
  while i < n {
    let oc: Int = f.outcomes[i];
    if oc == CMPL_VIOLATION {
      let sv: Int = f.severities[i];
      total = total + cmpl_severity_weight(sv);
    }
    i = i + 1;
  }
  return total;
}

/// Waived score: the sum of cmpl_severity_weight over CMPL_WAIVED findings.
/// It is reported separately from the risk score so waivers never mask risk.
/// Params: f - the findings.
/// Returns: the non-negative score. Error case: none. Complexity: O(n).
pub fn cmpl_waived_score(f: &Findings) -> Int {
  let n = _cmpl_findings_n(f);
  var total = 0;
  var i = 0;
  while i < n {
    let oc: Int = f.outcomes[i];
    if oc == CMPL_WAIVED {
      let sv: Int = f.severities[i];
      total = total + cmpl_severity_weight(sv);
    }
    i = i + 1;
  }
  return total;
}

/// Canonical severity name: "info", "low", "medium", "high", "critical";
/// "unknown" for any other code.
/// Params: severity - severity code.
/// Returns: the lowercase name. Error case: none. Complexity: O(1).
pub fn cmpl_severity_name(severity: Int) -> Str {
  if severity == CMPL_SEV_INFO {
    return "info";
  }
  if severity == CMPL_SEV_LOW {
    return "low";
  }
  if severity == CMPL_SEV_MEDIUM {
    return "medium";
  }
  if severity == CMPL_SEV_HIGH {
    return "high";
  }
  if severity == CMPL_SEV_CRITICAL {
    return "critical";
  }
  return "unknown";
}

/// Canonical outcome name: "pass", "violation", "waived",
/// "not-applicable"; "unknown" for any other code.
/// Params: outcome - CMPL_* outcome code.
/// Returns: the lowercase name. Error case: none. Complexity: O(1).
pub fn cmpl_outcome_name(outcome: Int) -> Str {
  if outcome == CMPL_PASS {
    return "pass";
  }
  if outcome == CMPL_VIOLATION {
    return "violation";
  }
  if outcome == CMPL_WAIVED {
    return "waived";
  }
  if outcome == CMPL_NOT_APPLICABLE {
    return "not-applicable";
  }
  return "unknown";
}

// --------------------------------------------------
//  Report
// --------------------------------------------------

// Escape one report field: LF -> the two characters "\n", '|' -> "\|".
// Backslash itself is not escaped (same grammar as xiom.audit export); the
// report is field-parseable only when ids/details contain neither sequence.
fn _cmpl_escape(s: Str) -> Str {
  var out = "";
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i) as Int;
    if b == 10 {
      out = out + "\\" + "n";
    } elif b == 124 {
      out = out + "\\" + "|";
    } else {
      out = out + string.str_slice(s, i, i + 1);
    }
    i = i + 1;
  }
  return out;
}

/// Canonical findings report (LF-joined, no trailing LF):
///   compliance-report v1
///   findings=<n> pass=<p> violation=<v> waived=<w> not-applicable=<na>
///   violations critical=<c> high=<h> medium=<m> low=<l> info=<i> other=<o>
///   score=<s> waived_score=<ws>
///   <index>|<rule id>|<severity>|<outcome>|<detail>
/// one line per finding, index ascending. `other` counts violations whose
/// severity is outside 0..4; `score` is cmpl_risk_score and `waived_score`
/// is cmpl_waived_score. Ids and details are escaped (LF -> "\n", '|' ->
/// "\|"); the header words are fixed literals. An empty findings record
/// reports all-zero counts.
/// Params: f - the findings.
/// Returns: the report text. Error case: none. Complexity: O(total text).
pub fn cmpl_report(f: &Findings) -> Str {
  let n = _cmpl_findings_n(f);
  let vcount = cmpl_count(f, CMPL_VIOLATION);
  let named = cmpl_severity_count(f, CMPL_VIOLATION, CMPL_SEV_CRITICAL)
    + cmpl_severity_count(f, CMPL_VIOLATION, CMPL_SEV_HIGH)
    + cmpl_severity_count(f, CMPL_VIOLATION, CMPL_SEV_MEDIUM)
    + cmpl_severity_count(f, CMPL_VIOLATION, CMPL_SEV_LOW)
    + cmpl_severity_count(f, CMPL_VIOLATION, CMPL_SEV_INFO);
  var out = "compliance-report v1\n";
  out = out + "findings=" + convert.int_to_string(n);
  out = out + " pass=" + convert.int_to_string(cmpl_count(f, CMPL_PASS));
  out = out + " violation=" + convert.int_to_string(vcount);
  out = out + " waived=" + convert.int_to_string(cmpl_count(f, CMPL_WAIVED));
  out = out + " not-applicable=" + convert.int_to_string(cmpl_count(f, CMPL_NOT_APPLICABLE));
  out = out + "\nviolations";
  out = out + " critical=" + convert.int_to_string(cmpl_severity_count(f, CMPL_VIOLATION, CMPL_SEV_CRITICAL));
  out = out + " high=" + convert.int_to_string(cmpl_severity_count(f, CMPL_VIOLATION, CMPL_SEV_HIGH));
  out = out + " medium=" + convert.int_to_string(cmpl_severity_count(f, CMPL_VIOLATION, CMPL_SEV_MEDIUM));
  out = out + " low=" + convert.int_to_string(cmpl_severity_count(f, CMPL_VIOLATION, CMPL_SEV_LOW));
  out = out + " info=" + convert.int_to_string(cmpl_severity_count(f, CMPL_VIOLATION, CMPL_SEV_INFO));
  out = out + " other=" + convert.int_to_string(vcount - named);
  out = out + "\nscore=" + convert.int_to_string(cmpl_risk_score(f));
  out = out + " waived_score=" + convert.int_to_string(cmpl_waived_score(f));
  var i = 0;
  while i < n {
    let rid: Str = f.rule_ids[i];
    let sv: Int = f.severities[i];
    let oc: Int = f.outcomes[i];
    let det: Str = f.details[i];
    out = out + "\n" + convert.int_to_string(i) + "|" + _cmpl_escape(rid) + "|" + cmpl_severity_name(sv) + "|" + cmpl_outcome_name(oc) + "|" + _cmpl_escape(det);
    i = i + 1;
  }
  return out;
}
