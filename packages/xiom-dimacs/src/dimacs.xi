// XIOM -- xiom.dimacs: DIMACS CNF parsing and canonical emission
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small, dependency-free codec for the DIMACS CNF subset described in
// SPEC.md:
//   * `c` comment lines and blank lines are ignored anywhere;
//   * exactly one `p cnf <vars> <clauses>` header, before any clause data;
//   * clauses are runs of non-zero signed decimal literals terminated by 0,
//     in a single token stream: one clause may span several lines and several
//     clauses may share one line.
// The parser is strict: it validates the header counts, the 1..vars literal
// range, the presence of every clause terminator, the absence of any token
// after the last declared clause, negative zero and decimal overflow.
//
// Clauses are stored flat: `lits` holds every literal in document order and
// `offs` (clauses + 1 entries, offs[0] = 0) holds the clause boundaries, so
// clause k is lits[offs[k] .. offs[k+1]]. XIOM v0.61.3 cannot hold
// Vec[StructType], which is why there is no Vec[Clause].
//
// Language notes (XIOM v0.61.3): free functions only; Ok/Err are constructed
// only in the leaf helpers _ok_cnf/_err_cnf (Result construction in other
// shapes miscompiles); every Vec[Int] element read goes through a local.

module xiom.dimacs

use xiom.string;
use xiom.convert;

// --------------------------------------------------
//  CNF container
// --------------------------------------------------

// A parsed (or built) CNF formula. Invariants: vars >= 0, clauses >= 0,
// offs.len() == clauses + 1, offs[0] == 0, offs[clauses] == lits.len(), and
// every literal in lits is non-zero with |literal| <= vars.
pub type Cnf = {
  vars: Int;
  clauses: Int;
  lits: Vec[Int];
  offs: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Cnf, Str].
fn _ok_cnf(v: Cnf) -> Result[Cnf, Str] {
  return Ok(v);
}

// Err(m) for Result[Cnf, Str].
fn _err_cnf(m: Str) -> Result[Cnf, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and predicates
// --------------------------------------------------

const _DM_TAB: UInt8 = 9u8;
const _DM_LF: UInt8 = 10u8;
const _DM_CR: UInt8 = 13u8;
const _DM_SPACE: UInt8 = 32u8;
const _DM_MINUS: UInt8 = 45u8;
const _DM_DIGIT_0: UInt8 = 48u8;
const _DM_DIGIT_9: UInt8 = 57u8;
const _DM_C: UInt8 = 99u8;
const _DM_N: UInt8 = 110u8;
const _DM_F: UInt8 = 102u8;
const _DM_P: UInt8 = 112u8;

// Largest Int; a local copy because the package imports no core constants.
const _DM_INT_MAX: Int = 9223372036854775807;

// Horizontal whitespace inside a line: space or tab.
fn _is_hspace(b: UInt8) -> Bool {
  return b == _DM_SPACE || b == _DM_TAB;
}

// ASCII decimal digit: 0-9.
fn _is_digit(b: UInt8) -> Bool {
  return b >= _DM_DIGIT_0 && b <= _DM_DIGIT_9;
}

// True when text[i..i+3] is the literal word "cnf" (requires i + 3 <= len).
fn _is_cnf_word(text: Str, i: Int) -> Bool {
  if i + 3 > text.len() {
    return false;
  }
  if string.byte_at(text, i) != _DM_C {
    return false;
  }
  if string.byte_at(text, i + 1) != _DM_N {
    return false;
  }
  if string.byte_at(text, i + 2) != _DM_F {
    return false;
  }
  return true;
}

// Scan an unsigned decimal run starting at i (caller guarantees a digit at i).
// Returns (value, index after the run, status) where status is 0 on success
// and 1 when the value does not fit in an Int (the value is then 0).
fn _scan_uint(text: Str, i: Int, n: Int) -> (Int, Int, Int) {
  var acc: Int = 0;
  var j = i;
  while j < n {
    let b = string.byte_at(text, j);
    if !_is_digit(b) {
      break;
    }
    let code: Int = (b as Int) & 0xFF;
    let dv: Int = code - 48;
    if acc > (_DM_INT_MAX - dv) / 10 {
      return (0, j, 1);
    }
    acc = acc * 10 + dv;
    j = j + 1;
  }
  return (acc, j, 0);
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse a DIMACS CNF document (the subset in SPEC.md).
/// Params: text - the whole document. Comment lines (first non-whitespace
/// byte `c`) and blank lines are ignored anywhere, including between the
/// lines of a split clause. Exactly one `p cnf <vars> <clauses>` header must
/// precede the clause data; both counts are non-negative decimal integers.
/// Returns: Ok(Cnf) whose declared counts match the parsed data: every clause
/// is terminated by 0 (a clause may span several lines), and no token may
/// follow the last declared clause. Literals are non-zero signed integers
/// with 1 <= |literal| <= vars; a literal 0 closes the clause in progress,
/// including the empty clause (a bare 0).
/// Error case: Err(message) from the SPEC.md error catalog; line-local
/// problems name the 1-based source line.
/// Complexity: O(n) over the document with O(1) work per byte.
pub fn dimacs_parse(text: Str) -> Result[Cnf, Str] {
  let n = text.len();
  var vars: Int = 0;
  var declared: Int = 0;
  var has_header = false;
  var lits = Vec[Int].new();
  var offs = Vec[Int].new();
  offs.push(0);
  var done: Int = 0;
  var open_lits: Int = 0;
  var i = 0;
  var line = 1;
  var at_start = true;
  while i < n {
    let b = string.byte_at(text, i);
    if b == _DM_LF {
      i = i + 1;
      line = line + 1;
      at_start = true;
    } elif b == _DM_CR {
      i = i + 1;
      if i < n && string.byte_at(text, i) == _DM_LF {
        i = i + 1;
      }
      line = line + 1;
      at_start = true;
    } elif _is_hspace(b) {
      i = i + 1;
    } elif at_start && b == _DM_C {
      while i < n {
        let c = string.byte_at(text, i);
        if c == _DM_LF || c == _DM_CR {
          break;
        }
        i = i + 1;
      }
    } elif at_start && b == _DM_P {
      if has_header {
        return _err_cnf("dimacs: duplicate header at line " + int_to_string(line));
      }
      var j = i + 1;
      if j >= n || !_is_hspace(string.byte_at(text, j)) {
        return _err_cnf("dimacs: malformed header at line " + int_to_string(line));
      }
      while j < n && _is_hspace(string.byte_at(text, j)) {
        j = j + 1;
      }
      if !_is_cnf_word(text, j) {
        return _err_cnf("dimacs: malformed header at line " + int_to_string(line));
      }
      j = j + 3;
      if j >= n || !_is_hspace(string.byte_at(text, j)) {
        return _err_cnf("dimacs: malformed header at line " + int_to_string(line));
      }
      while j < n && _is_hspace(string.byte_at(text, j)) {
        j = j + 1;
      }
      if j >= n || !_is_digit(string.byte_at(text, j)) {
        return _err_cnf("dimacs: invalid variable count at line " + int_to_string(line));
      }
      let rv = _scan_uint(text, j, n);
      let vcount = rv.0;
      let after_v = rv.1;
      let vstatus = rv.2;
      if vstatus != 0 {
        return _err_cnf("dimacs: invalid variable count at line " + int_to_string(line));
      }
      j = after_v;
      if j >= n || !_is_hspace(string.byte_at(text, j)) {
        return _err_cnf("dimacs: malformed header at line " + int_to_string(line));
      }
      while j < n && _is_hspace(string.byte_at(text, j)) {
        j = j + 1;
      }
      if j >= n || !_is_digit(string.byte_at(text, j)) {
        return _err_cnf("dimacs: invalid clause count at line " + int_to_string(line));
      }
      let rc = _scan_uint(text, j, n);
      let ccount = rc.0;
      let after_c = rc.1;
      let cstatus = rc.2;
      if cstatus != 0 {
        return _err_cnf("dimacs: invalid clause count at line " + int_to_string(line));
      }
      j = after_c;
      while j < n && _is_hspace(string.byte_at(text, j)) {
        j = j + 1;
      }
      if j < n {
        let e = string.byte_at(text, j);
        if e != _DM_LF && e != _DM_CR {
          return _err_cnf("dimacs: malformed header at line " + int_to_string(line));
        }
      }
      vars = vcount;
      declared = ccount;
      has_header = true;
      i = j;
    } elif !has_header {
      return _err_cnf("dimacs: missing header at line " + int_to_string(line));
    } elif done >= declared {
      return _err_cnf("dimacs: token after final clause at line " + int_to_string(line));
    } else {
      var neg = false;
      var j = i;
      if b == _DM_MINUS {
        neg = true;
        j = j + 1;
      }
      if j >= n || !_is_digit(string.byte_at(text, j)) {
        return _err_cnf("dimacs: invalid token at line " + int_to_string(line));
      }
      let rr = _scan_uint(text, j, n);
      let mag = rr.0;
      let after_lit = rr.1;
      let lstatus = rr.2;
      if lstatus != 0 {
        return _err_cnf("dimacs: integer overflow at line " + int_to_string(line));
      }
      if neg && mag == 0 {
        return _err_cnf("dimacs: negative literal 0 at line " + int_to_string(line));
      }
      if mag > vars {
        return _err_cnf("dimacs: literal out of range at line " + int_to_string(line));
      }
      if mag == 0 {
        offs.push(lits.len());
        done = done + 1;
        open_lits = 0;
      } else {
        if neg {
          lits.push(0 - mag);
        } else {
          lits.push(mag);
        }
        open_lits = open_lits + 1;
      }
      i = after_lit;
      at_start = false;
    }
  }
  if !has_header {
    return _err_cnf("dimacs: missing header at end of input");
  }
  if open_lits > 0 {
    return _err_cnf("dimacs: unterminated clause at end of input");
  }
  if done != declared {
    return _err_cnf("dimacs: clause count mismatch: expected " + int_to_string(declared) + ", got " + int_to_string(done));
  }
  return _ok_cnf(Cnf{
    vars: vars;
    clauses: declared;
    lits: lits;
    offs: offs;
  });
}

// --------------------------------------------------
//  Emission
// --------------------------------------------------

/// Serialize a CNF formula in canonical DIMACS CNF form.
/// Params: c - a well-formed formula (as returned by dimacs_parse or built
/// with dimacs_new/dimacs_add_clause).
/// Returns: the canonical text: `p cnf <vars> <clauses>` then one clause per
/// line, literals separated by single spaces and followed by ` 0`; the empty
/// clause is the single token `0`; every line, including the header, ends
/// with LF. Zero clauses yield only the header line.
/// Error case: none; the formula's invariants are assumed (see Cnf).
/// Complexity: O(n) over the output.
pub fn dimacs_emit(c: &Cnf) -> Str {
  var out = "p cnf " + int_to_string(c.vars) + " " + int_to_string(c.clauses) + "\n";
  var k = 0;
  while k < c.clauses {
    let start: Int = c.offs[k];
    let end: Int = c.offs[k + 1];
    var j = start;
    while j < end {
      let lit: Int = c.lits[j];
      out = out + int_to_string(lit) + " ";
      j = j + 1;
    }
    out = out + "0\n";
    k = k + 1;
  }
  return out;
}

// --------------------------------------------------
//  Construction
// --------------------------------------------------

/// A formula with `vars` variables and no clauses.
/// Params: vars - the variable count (>= 0; not validated).
/// Returns: a fresh Cnf with clauses = 0 and empty flat storage.
/// Error case: none.
/// Complexity: O(1).
pub fn dimacs_new(vars: Int) -> Cnf {
  var offs = Vec[Int].new();
  offs.push(0);
  return Cnf{
    vars: vars;
    clauses: 0;
    lits: Vec[Int].new();
    offs: offs;
  };
}

/// Append one clause to `c`.
/// Params: c - the formula to mutate; clause - the clause's literals in
/// order (each should be non-zero with |literal| <= c.vars; not validated).
/// Returns: nothing. `c.clauses` grows by one and the flat storage gains the
/// clause's literals plus one boundary offset.
/// Error case: none.
/// Complexity: O(|clause|).
pub fn dimacs_add_clause(c: &mut Cnf, clause: &Vec[Int]) {
  var j = 0;
  while j < clause.len() {
    let lit: Int = clause[j];
    c.lits.push(lit);
    j = j + 1;
  }
  c.clauses = c.clauses + 1;
  c.offs.push(c.lits.len());
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Declared variable count of `c`.
/// Params: c - the formula.
/// Returns: c.vars.
/// Error case: none.
/// Complexity: O(1).
pub fn dimacs_var_count(c: &Cnf) -> Int {
  return c.vars;
}

/// Clause count of `c`.
/// Params: c - the formula.
/// Returns: c.clauses.
/// Error case: none.
/// Complexity: O(1).
pub fn dimacs_clause_count(c: &Cnf) -> Int {
  return c.clauses;
}

/// Total number of literals in `c` (sum of every clause's width).
/// Params: c - the formula.
/// Returns: the flat literal count.
/// Error case: none.
/// Complexity: O(1).
pub fn dimacs_literal_count(c: &Cnf) -> Int {
  return c.lits.len();
}

/// Literal at flat position `i` (document order, across clauses).
/// Params: c - the formula; i - zero-based flat index.
/// Returns: the signed literal; 0 when `i` is negative or out of range
/// (literals themselves are never 0, so 0 is an unambiguous sentinel).
/// Error case: none.
/// Complexity: O(1).
pub fn dimacs_literal(c: &Cnf, i: Int) -> Int {
  if i < 0 || i >= c.lits.len() {
    return 0;
  }
  let lit: Int = c.lits[i];
  return lit;
}

/// Flat index of clause `k`'s first literal.
/// Params: c - the formula; k - zero-based clause index.
/// Returns: offs[k]; -1 when `k` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn dimacs_clause_start(c: &Cnf, k: Int) -> Int {
  if k < 0 || k >= c.clauses {
    return -1;
  }
  let s: Int = c.offs[k];
  return s;
}

/// Number of literals in clause `k`.
/// Params: c - the formula; k - zero-based clause index.
/// Returns: offs[k + 1] - offs[k] (0 for the empty clause); -1 when `k` is
/// negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn dimacs_clause_len(c: &Cnf, k: Int) -> Int {
  if k < 0 || k >= c.clauses {
    return -1;
  }
  let a: Int = c.offs[k];
  let b: Int = c.offs[k + 1];
  return b - a;
}

/// Literal `j` of clause `k`.
/// Params: c - the formula; k - zero-based clause index; j - zero-based
/// position inside the clause.
/// Returns: the signed literal; 0 when `k` or `j` is out of range (literals
/// are never 0, so 0 is the out-of-range sentinel; it is also what an empty
/// clause's nonexistent literal reads as).
/// Error case: none.
/// Complexity: O(1).
pub fn dimacs_clause_literal(c: &Cnf, k: Int, j: Int) -> Int {
  if k < 0 || k >= c.clauses {
    return 0;
  }
  let a: Int = c.offs[k];
  let b: Int = c.offs[k + 1];
  if j < 0 || j >= b - a {
    return 0;
  }
  let lit: Int = c.lits[a + j];
  return lit;
}
