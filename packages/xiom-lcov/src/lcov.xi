// XIOM -- xiom.lcov: LCOV tracefile parser and canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no I/O (in-memory Str only).
//
// A line-based parser and emitter for the documented LCOV tracefile subset
// in SPEC.md:
//   * TN:<test name>                  -- test label for the next SF section
//   * SF:<source file>                -- opens a file section
//   * FN:<line>,<name>                -- function definition
//   * FNDA:<count>,<name>             -- function execution count
//   * FNF:<n> / FNH:<n>               -- declared functions found / hit
//   * DA:<line>,<count>[,<checksum>]  -- line execution data
//   * LF:<n> / LH:<n>                 -- declared lines found / hit
//   * BRDA:<line>,<block>,<branch>,<taken|->  -- branch data
//   * BRF:<n> / BRH:<n>               -- declared branches found / hit
//   * end_of_record                   -- closes the current file section
// Blank (empty or SPACE/TAB-only) lines are ignored; one CR before the LF is
// dropped, so LF and CRLF inputs both work. See SPEC.md for the exact record
// grammar, the canonical emit order and the error catalog.
//
// Model: one parsed tracefile is an LcovDoc with flat, index-aligned parallel
// vectors because XIOM v0.61.3 cannot hold Vec[StructType]. Each file section
// owns a range (offset,count) into four record stores: functions (FN),
// function counts (FNDA), line data (DA) and branch data (BRDA). Every push
// on one store is mirrored on its count array, so ranges never drift; the
// accessors clamp every range to the shortest parallel arrays, so a
// hand-built doc can never read out of range either. Declared FNF/FNH/LF/LH/
// BRF/BRH values are stored (-1 = absent) and the corresponding computed
// values are derived from the records; a declared/computed mismatch is
// tolerated at parse time and exposed through the lcov_*_mismatch accessors.
//
// Language notes (XIOM v0.61.3): free functions only; Str equality goes
// through xiom.string.compare.str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison); every Vec element
// read is bound to a typed local first; Ok/Err are constructed only in the
// leaf helpers _ok_doc/_err_doc because direct Result construction in other
// shapes miscompiles in this compiler.

module xiom.lcov

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[LcovDoc, Str].
fn _ok_doc(d: LcovDoc) -> Result[LcovDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[LcovDoc, Str].
fn _err_doc(m: Str) -> Result[LcovDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (all ASCII, every comparison is with a byte < 128)
// --------------------------------------------------

const _LC_TAB: UInt8 = 9u8;
const _LC_LF: UInt8 = 10u8;
const _LC_CR: UInt8 = 13u8;
const _LC_SPACE: UInt8 = 32u8;
const _LC_COMMA: UInt8 = 44u8;
const _LC_MINUS: UInt8 = 45u8;
const _LC_DIGIT_0: UInt8 = 48u8;
const _LC_DIGIT_9: UInt8 = 57u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One parsed LCOV tracefile, stored flat.
/// File section f (0-based, in stream order) is described by sf[f] (its
/// source path) and tn[f] (its test name; "" when none was pending). Its
/// records live in four global stores, each addressed by the range
/// (offset[f], count[f]) of that file:
///   * functions:        fn_line, fn_name
///   * function counts:  fnda_hits, fnda_name
///   * line data:        da_line, da_hits, da_checksum + da_cs (1 = the DA
///                       record carried a checksum, 0 = two-field record)
///   * branch data:      brda_line, brda_block, brda_branch, brda_taken
///                       (taken = -1 encodes the "-" sentinel)
/// Declared FNF/FNH/LF/LH/BRF/BRH records are stored per file in decl_fnf,
/// decl_fnh, decl_lf, decl_lh, decl_brf, decl_brh; -1 means "absent" and a
/// duplicate declaration overwrites the previous one. All per-file arrays
/// are kept index-aligned by the parser; _file_count is their shortest
/// length and every range is clamped, so a hand-built doc cannot read out of
/// range.
pub type LcovDoc = {
  sf: Vec[Str];
  tn: Vec[Str];
  decl_fnf: Vec[Int];
  decl_fnh: Vec[Int];
  decl_lf: Vec[Int];
  decl_lh: Vec[Int];
  decl_brf: Vec[Int];
  decl_brh: Vec[Int];
  fn_off: Vec[Int];
  fn_n: Vec[Int];
  fn_line: Vec[Int];
  fn_name: Vec[Str];
  fnda_off: Vec[Int];
  fnda_n: Vec[Int];
  fnda_hits: Vec[Int];
  fnda_name: Vec[Str];
  da_off: Vec[Int];
  da_n: Vec[Int];
  da_line: Vec[Int];
  da_hits: Vec[Int];
  da_cs: Vec[Int];
  da_checksum: Vec[Str];
  brda_off: Vec[Int];
  brda_n: Vec[Int];
  brda_line: Vec[Int];
  brda_block: Vec[Str];
  brda_branch: Vec[Str];
  brda_taken: Vec[Int];
}

// --------------------------------------------------
//  Small text helpers
// --------------------------------------------------

// True when `s` is empty or holds only ASCII spaces and tabs.
fn _is_blank(s: Str) -> Bool {
  var i = 0;
  let n = s.len();
  while i < n {
    let b = string.byte_at(s, i);
    if b != _LC_SPACE && b != _LC_TAB {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Byte index of the first ',' at or after `from`, or -1 when there is none.
fn _comma_at(s: Str, from: Int) -> Int {
  var i = from;
  let n = s.len();
  while i < n {
    if string.byte_at(s, i) == _LC_COMMA {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Parse the decimal run s[from..to) into a non-negative Int.
// Returns: the value for a valid run (a run of zeros yields 0); -1 when the
// run is empty, carries a non-digit byte, has more than 10 digits (so no
// overflow is possible) or exceeds 1000000000; -2 when the run starts with
// '-' and has at least one more byte.
fn _parse_num(s: Str, from: Int, to: Int) -> Int {
  if from >= to {
    return -1;
  }
  if string.byte_at(s, from) == _LC_MINUS {
    if from + 1 < to {
      return -2;
    }
    return -1;
  }
  if to - from > 10 {
    return -1;
  }
  var v = 0;
  var i = from;
  while i < to {
    let b = string.byte_at(s, i);
    if b < _LC_DIGIT_0 || b > _LC_DIGIT_9 {
      return -1;
    }
    v = v * 10 + (((b as Int) & 0xFF) - 48);
    if v > 1000000000 {
      return -1;
    }
    i = i + 1;
  }
  return v;
}

// Smaller of two Ints.
fn _min2(a: Int, b: Int) -> Int {
  if a < b {
    return a;
  }
  return b;
}

// Count of range [off, off+count) inside an array of length `total`,
// clamped so the result is always a valid sub-range. 0 when the range is
// empty, negative or starts at or past the end.
fn _span(off: Int, count: Int, total: Int) -> Int {
  if off < 0 || count <= 0 || off >= total {
    return 0;
  }
  let room = total - off;
  if count > room {
    return room;
  }
  return count;
}

// --------------------------------------------------
//  Error message builders (the catalog is in SPEC.md)
// --------------------------------------------------

// Unknown record prefix; <L> is the 1-based line number.
fn _err_unknown(line_no: Int) -> Str {
  return "lcov: unknown record at " + int_to_string(line_no);
}

// A file-scoped record outside any open SF section.
fn _err_outside(line_no: Int) -> Str {
  return "lcov: record outside source file at " + int_to_string(line_no);
}

// Wrong number of comma-separated fields.
fn _err_fields(line_no: Int) -> Str {
  return "lcov: bad field count at " + int_to_string(line_no);
}

// A required field is empty.
fn _err_empty(line_no: Int) -> Str {
  return "lcov: empty field at " + int_to_string(line_no);
}

// A numeric field: code -2 is a negative sign, anything else a non-numeric
// (or overflowing) run.
fn _err_num(line_no: Int, code: Int) -> Str {
  if code == -2 {
    return "lcov: negative number at " + int_to_string(line_no);
  }
  return "lcov: non-numeric field at " + int_to_string(line_no);
}

// A file section opened at line `sf_line` was never closed (EOF, or a new
// SF record while it was still open).
fn _err_unclosed(sf_line: Int) -> Str {
  return "lcov: missing end_of_record at " + int_to_string(sf_line);
}

// --------------------------------------------------
//  File section and record stores
// --------------------------------------------------

// Append one file section to `d`, opening its four empty record ranges.
// Params: d - the document to mutate; source - the SF path (non-empty; the
// parser enforces that); test_name - the pending test name ("" = none).
// Returns: nothing.
// Error case: none.
// Complexity: O(1).
fn _file_push(d: &mut LcovDoc, source: Str, test_name: Str) {
  d.sf.push(source);
  d.tn.push(test_name);
  d.decl_fnf.push(-1);
  d.decl_fnh.push(-1);
  d.decl_lf.push(-1);
  d.decl_lh.push(-1);
  d.decl_brf.push(-1);
  d.decl_brh.push(-1);
  d.fn_off.push(d.fn_line.len());
  d.fn_n.push(0);
  d.fnda_off.push(d.fnda_hits.len());
  d.fnda_n.push(0);
  d.da_off.push(d.da_line.len());
  d.da_n.push(0);
  d.brda_off.push(d.brda_line.len());
  d.brda_n.push(0);
}

// Append one FN record to the open file section.
// Params: d - the document; rest - the record body after "FN:"; line_no - the
// 1-based line number for error messages.
// Returns: "" on success, else the catalog message.
// Complexity: O(body length).
fn _push_fn(d: &mut LcovDoc, rest: Str, line_no: Int) -> Str {
  let n = rest.len();
  let c1 = _comma_at(rest, 0);
  if c1 < 0 {
    return _err_fields(line_no);
  }
  if _comma_at(rest, c1 + 1) >= 0 {
    return _err_fields(line_no);
  }
  let line = _parse_num(rest, 0, c1);
  if line < 0 {
    return _err_num(line_no, line);
  }
  let name = string.str_slice(rest, c1 + 1, n);
  if compare.str_compare(name, "") == 0 {
    return _err_empty(line_no);
  }
  let f = d.sf.len() - 1;
  d.fn_line.push(line);
  d.fn_name.push(name);
  d.fn_n[f] = d.fn_n[f] + 1;
  return "";
}

// Append one FNDA record to the open file section.
// Params: d - the document; rest - the record body after "FNDA:"; line_no -
// the 1-based line number for error messages.
// Returns: "" on success, else the catalog message.
// Complexity: O(body length).
fn _push_fnda(d: &mut LcovDoc, rest: Str, line_no: Int) -> Str {
  let n = rest.len();
  let c1 = _comma_at(rest, 0);
  if c1 < 0 {
    return _err_fields(line_no);
  }
  if _comma_at(rest, c1 + 1) >= 0 {
    return _err_fields(line_no);
  }
  let hits = _parse_num(rest, 0, c1);
  if hits < 0 {
    return _err_num(line_no, hits);
  }
  let name = string.str_slice(rest, c1 + 1, n);
  if compare.str_compare(name, "") == 0 {
    return _err_empty(line_no);
  }
  let f = d.sf.len() - 1;
  d.fnda_hits.push(hits);
  d.fnda_name.push(name);
  d.fnda_n[f] = d.fnda_n[f] + 1;
  return "";
}

// Append one DA record to the open file section. Two or three fields: a
// third field is the optional checksum and may be any non-empty text.
// Params: d - the document; rest - the record body after "DA:"; line_no -
// the 1-based line number for error messages.
// Returns: "" on success, else the catalog message.
// Complexity: O(body length).
fn _push_da(d: &mut LcovDoc, rest: Str, line_no: Int) -> Str {
  let n = rest.len();
  let c1 = _comma_at(rest, 0);
  if c1 < 0 {
    return _err_fields(line_no);
  }
  var c2 = _comma_at(rest, c1 + 1);
  if c2 >= 0 {
    if _comma_at(rest, c2 + 1) >= 0 {
      return _err_fields(line_no);
    }
  } else {
    c2 = n;
  }
  let line = _parse_num(rest, 0, c1);
  if line < 0 {
    return _err_num(line_no, line);
  }
  let hits = _parse_num(rest, c1 + 1, c2);
  if hits < 0 {
    return _err_num(line_no, hits);
  }
  var present = 0;
  var sum = "";
  if c2 < n {
    sum = string.str_slice(rest, c2 + 1, n);
    if compare.str_compare(sum, "") == 0 {
      return _err_empty(line_no);
    }
    present = 1;
  }
  let f = d.sf.len() - 1;
  d.da_line.push(line);
  d.da_hits.push(hits);
  d.da_cs.push(present);
  d.da_checksum.push(sum);
  d.da_n[f] = d.da_n[f] + 1;
  return "";
}

// Append one BRDA record to the open file section. Exactly four fields; the
// block and branch fields are stored verbatim (non-empty), and the taken
// field is a non-negative count or the bare "-" sentinel (stored as -1).
// Params: d - the document; rest - the record body after "BRDA:"; line_no -
// the 1-based line number for error messages.
// Returns: "" on success, else the catalog message.
// Complexity: O(body length).
fn _push_brda(d: &mut LcovDoc, rest: Str, line_no: Int) -> Str {
  let n = rest.len();
  let c1 = _comma_at(rest, 0);
  if c1 < 0 {
    return _err_fields(line_no);
  }
  let c2 = _comma_at(rest, c1 + 1);
  if c2 < 0 {
    return _err_fields(line_no);
  }
  let c3 = _comma_at(rest, c2 + 1);
  if c3 < 0 {
    return _err_fields(line_no);
  }
  if _comma_at(rest, c3 + 1) >= 0 {
    return _err_fields(line_no);
  }
  let line = _parse_num(rest, 0, c1);
  if line < 0 {
    return _err_num(line_no, line);
  }
  let block = string.str_slice(rest, c1 + 1, c2);
  if compare.str_compare(block, "") == 0 {
    return _err_empty(line_no);
  }
  let branch = string.str_slice(rest, c2 + 1, c3);
  if compare.str_compare(branch, "") == 0 {
    return _err_empty(line_no);
  }
  let taken_s = string.str_slice(rest, c3 + 1, n);
  var taken = 0;
  if compare.str_compare(taken_s, "-") == 0 {
    taken = -1;
  } else {
    taken = _parse_num(rest, c3 + 1, n);
    if taken < 0 {
      return _err_num(line_no, taken);
    }
  }
  let f = d.sf.len() - 1;
  d.brda_line.push(line);
  d.brda_block.push(block);
  d.brda_branch.push(branch);
  d.brda_taken.push(taken);
  d.brda_n[f] = d.brda_n[f] + 1;
  return "";
}

// Store one declared FNF/FNH/LF/LH/BRF/BRH value on the open file section.
// The body must be exactly one unsigned number.
// Params: d - the document; rest - the record body after the prefix;
// line_no - the 1-based line number for error messages; kind - 0 = FNF,
// 1 = FNH, 2 = LF, 3 = LH, 4 = BRF, 5 = BRH.
// Returns: "" on success, else the catalog message.
// Complexity: O(body length).
fn _push_decl(d: &mut LcovDoc, rest: Str, line_no: Int, kind: Int) -> Str {
  if _comma_at(rest, 0) >= 0 {
    return _err_fields(line_no);
  }
  let v = _parse_num(rest, 0, rest.len());
  if v < 0 {
    return _err_num(line_no, v);
  }
  let f = d.sf.len() - 1;
  if kind == 0 {
    d.decl_fnf[f] = v;
  } elif kind == 1 {
    d.decl_fnh[f] = v;
  } elif kind == 2 {
    d.decl_lf[f] = v;
  } elif kind == 3 {
    d.decl_lh[f] = v;
  } elif kind == 4 {
    d.decl_brf[f] = v;
  } else {
    d.decl_brh[f] = v;
  }
  return "";
}

// True when `line` uses one of the file-scoped record prefixes or is
// "end_of_record". Used to tell "record outside source file" from "unknown
// record" when no section is open.
fn _is_file_record(line: Str) -> Bool {
  if string.str_starts_with(line, "FN:") {
    return true;
  }
  if string.str_starts_with(line, "FNDA:") {
    return true;
  }
  if string.str_starts_with(line, "FNF:") {
    return true;
  }
  if string.str_starts_with(line, "FNH:") {
    return true;
  }
  if string.str_starts_with(line, "DA:") {
    return true;
  }
  if string.str_starts_with(line, "LF:") {
    return true;
  }
  if string.str_starts_with(line, "LH:") {
    return true;
  }
  if string.str_starts_with(line, "BRDA:") {
    return true;
  }
  if string.str_starts_with(line, "BRF:") {
    return true;
  }
  if string.str_starts_with(line, "BRH:") {
    return true;
  }
  return compare.str_compare(line, "end_of_record") == 0;
}

// Dispatch one non-blank record line inside an open file section.
// Params: d - the document; line - the line (CR already dropped); line_no -
// the 1-based line number for error messages.
// Returns: "" on success, else the catalog message.
// Complexity: O(body length).
fn _consume_open(d: &mut LcovDoc, line: Str, line_no: Int) -> Str {
  if string.str_starts_with(line, "FN:") {
    return _push_fn(d, string.str_slice(line, 3, line.len()), line_no);
  }
  if string.str_starts_with(line, "FNDA:") {
    return _push_fnda(d, string.str_slice(line, 5, line.len()), line_no);
  }
  if string.str_starts_with(line, "FNF:") {
    return _push_decl(d, string.str_slice(line, 4, line.len()), line_no, 0);
  }
  if string.str_starts_with(line, "FNH:") {
    return _push_decl(d, string.str_slice(line, 4, line.len()), line_no, 1);
  }
  if string.str_starts_with(line, "DA:") {
    return _push_da(d, string.str_slice(line, 3, line.len()), line_no);
  }
  if string.str_starts_with(line, "LF:") {
    return _push_decl(d, string.str_slice(line, 3, line.len()), line_no, 2);
  }
  if string.str_starts_with(line, "LH:") {
    return _push_decl(d, string.str_slice(line, 3, line.len()), line_no, 3);
  }
  if string.str_starts_with(line, "BRDA:") {
    return _push_brda(d, string.str_slice(line, 5, line.len()), line_no);
  }
  if string.str_starts_with(line, "BRF:") {
    return _push_decl(d, string.str_slice(line, 4, line.len()), line_no, 4);
  }
  if string.str_starts_with(line, "BRH:") {
    return _push_decl(d, string.str_slice(line, 4, line.len()), line_no, 5);
  }
  return _err_unknown(line_no);
}

// --------------------------------------------------
//  Construction
// --------------------------------------------------

/// A fresh, empty document: no file sections, no records.
/// Params: none.
/// Returns: an empty LcovDoc.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_doc_new() -> LcovDoc {
  return LcovDoc{
    sf: Vec[Str].new();
    tn: Vec[Str].new();
    decl_fnf: Vec[Int].new();
    decl_fnh: Vec[Int].new();
    decl_lf: Vec[Int].new();
    decl_lh: Vec[Int].new();
    decl_brf: Vec[Int].new();
    decl_brh: Vec[Int].new();
    fn_off: Vec[Int].new();
    fn_n: Vec[Int].new();
    fn_line: Vec[Int].new();
    fn_name: Vec[Str].new();
    fnda_off: Vec[Int].new();
    fnda_n: Vec[Int].new();
    fnda_hits: Vec[Int].new();
    fnda_name: Vec[Str].new();
    da_off: Vec[Int].new();
    da_n: Vec[Int].new();
    da_line: Vec[Int].new();
    da_hits: Vec[Int].new();
    da_cs: Vec[Int].new();
    da_checksum: Vec[Str].new();
    brda_off: Vec[Int].new();
    brda_n: Vec[Int].new();
    brda_line: Vec[Int].new();
    brda_block: Vec[Str].new();
    brda_branch: Vec[Str].new();
    brda_taken: Vec[Int].new();
  };
}

// --------------------------------------------------
//  File section accessors
// --------------------------------------------------

// Number of index-aligned file sections: the shortest of the per-file
// parallel arrays, so a hand-built doc can never be read out of range.
fn _file_count(d: &LcovDoc) -> Int {
  var n = d.sf.len();
  if d.tn.len() < n { n = d.tn.len(); }
  if d.decl_fnf.len() < n { n = d.decl_fnf.len(); }
  if d.decl_fnh.len() < n { n = d.decl_fnh.len(); }
  if d.decl_lf.len() < n { n = d.decl_lf.len(); }
  if d.decl_lh.len() < n { n = d.decl_lh.len(); }
  if d.decl_brf.len() < n { n = d.decl_brf.len(); }
  if d.decl_brh.len() < n { n = d.decl_brh.len(); }
  if d.fn_off.len() < n { n = d.fn_off.len(); }
  if d.fn_n.len() < n { n = d.fn_n.len(); }
  if d.fnda_off.len() < n { n = d.fnda_off.len(); }
  if d.fnda_n.len() < n { n = d.fnda_n.len(); }
  if d.da_off.len() < n { n = d.da_off.len(); }
  if d.da_n.len() < n { n = d.da_n.len(); }
  if d.brda_off.len() < n { n = d.brda_off.len(); }
  if d.brda_n.len() < n { n = d.brda_n.len(); }
  return n;
}

/// Number of file (SF) sections in `d`.
/// Params: d - the document.
/// Returns: the count (0 for an empty document).
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_file_count(d: &LcovDoc) -> Int {
  return _file_count(d);
}

/// Source path of file section `f` (the SF record body).
/// Params: d - the document; f - the zero-based file index.
/// Returns: the path; "" when `f` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_file_source(d: &LcovDoc, f: Int) -> Str {
  if f < 0 || f >= _file_count(d) {
    return "";
  }
  let v: Str = d.sf[f];
  return v;
}

/// Test name that labelled file section `f` (the pending TN record, "" when
/// none). A TN record labels the next SF section, so TN records are attached
/// to the section they precede.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the test name; "" when absent or `f` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_file_test_name(d: &LcovDoc, f: Int) -> Str {
  if f < 0 || f >= _file_count(d) {
    return "";
  }
  let v: Str = d.tn[f];
  return v;
}

// --------------------------------------------------
//  Declared summary records (FNF/FNH/LF/LH/BRF/BRH)
// --------------------------------------------------

/// Declared FNF value of file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the last FNF value parsed for `f`; -1 when no FNF record was
/// present (or `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_declared_fnf(d: &LcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return -1;
  }
  let v: Int = d.decl_fnf[f];
  return v;
}

/// Declared FNH value of file section `f`; -1 when absent.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the declared value or -1.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_declared_fnh(d: &LcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return -1;
  }
  let v: Int = d.decl_fnh[f];
  return v;
}

/// Declared LF value of file section `f`; -1 when absent.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the declared value or -1.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_declared_lf(d: &LcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return -1;
  }
  let v: Int = d.decl_lf[f];
  return v;
}

/// Declared LH value of file section `f`; -1 when absent.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the declared value or -1.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_declared_lh(d: &LcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return -1;
  }
  let v: Int = d.decl_lh[f];
  return v;
}

/// Declared BRF value of file section `f`; -1 when absent.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the declared value or -1.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_declared_brf(d: &LcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return -1;
  }
  let v: Int = d.decl_brf[f];
  return v;
}

/// Declared BRH value of file section `f`; -1 when absent.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the declared value or -1.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_declared_brh(d: &LcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return -1;
  }
  let v: Int = d.decl_brh[f];
  return v;
}

// --------------------------------------------------
//  Computed summary values (derived from records)
// --------------------------------------------------

/// Computed FNF of file section `f`: the number of FN records.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_computed_fnf(d: &LcovDoc, f: Int) -> Int {
  return lcov_fn_count(d, f);
}

/// Computed FNH of file section `f`: the number of FNDA records with a
/// positive hit count. Duplicate names are counted once per record.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(records).
pub fn lcov_computed_fnh(d: &LcovDoc, f: Int) -> Int {
  let n = lcov_fnda_count(d, f);
  if n <= 0 {
    return 0;
  }
  let off: Int = d.fnda_off[f];
  var c = 0;
  var i = 0;
  while i < n {
    let h: Int = d.fnda_hits[off + i];
    if h > 0 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Computed LF of file section `f`: the number of DA records.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_computed_lf(d: &LcovDoc, f: Int) -> Int {
  return lcov_da_count(d, f);
}

/// Computed LH of file section `f`: the number of DA records with a positive
/// hit count.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(records).
pub fn lcov_computed_lh(d: &LcovDoc, f: Int) -> Int {
  let n = lcov_da_count(d, f);
  if n <= 0 {
    return 0;
  }
  let off: Int = d.da_off[f];
  var c = 0;
  var i = 0;
  while i < n {
    let h: Int = d.da_hits[off + i];
    if h > 0 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Computed BRF of file section `f`: the number of BRDA records.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_computed_brf(d: &LcovDoc, f: Int) -> Int {
  return lcov_brda_count(d, f);
}

/// Computed BRH of file section `f`: the number of BRDA records with a
/// taken count of at least 1. Both the "-" sentinel and an explicit 0 count
/// as not hit.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(records).
pub fn lcov_computed_brh(d: &LcovDoc, f: Int) -> Int {
  let n = lcov_brda_count(d, f);
  if n <= 0 {
    return 0;
  }
  let off: Int = d.brda_off[f];
  var c = 0;
  var i = 0;
  while i < n {
    let t: Int = d.brda_taken[off + i];
    if t >= 1 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

// --------------------------------------------------
//  Declared-vs-computed mismatch flags
// --------------------------------------------------

/// Declared/computed FNF mismatch of file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: true when a declared FNF record exists (>= 0) and differs from
/// lcov_computed_fnf; false when absent or equal.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_fnf_mismatch(d: &LcovDoc, f: Int) -> Bool {
  let decl = lcov_declared_fnf(d, f);
  if decl < 0 {
    return false;
  }
  return decl != lcov_computed_fnf(d, f);
}

/// Declared/computed FNH mismatch of file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: true when a declared FNH record exists and differs from
/// lcov_computed_fnh; false otherwise.
/// Error case: none.
/// Complexity: O(records).
pub fn lcov_fnh_mismatch(d: &LcovDoc, f: Int) -> Bool {
  let decl = lcov_declared_fnh(d, f);
  if decl < 0 {
    return false;
  }
  return decl != lcov_computed_fnh(d, f);
}

/// Declared/computed LF mismatch of file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: true when a declared LF record exists and differs from
/// lcov_computed_lf; false otherwise.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_lf_mismatch(d: &LcovDoc, f: Int) -> Bool {
  let decl = lcov_declared_lf(d, f);
  if decl < 0 {
    return false;
  }
  return decl != lcov_computed_lf(d, f);
}

/// Declared/computed LH mismatch of file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: true when a declared LH record exists and differs from
/// lcov_computed_lh; false otherwise.
/// Error case: none.
/// Complexity: O(records).
pub fn lcov_lh_mismatch(d: &LcovDoc, f: Int) -> Bool {
  let decl = lcov_declared_lh(d, f);
  if decl < 0 {
    return false;
  }
  return decl != lcov_computed_lh(d, f);
}

/// Declared/computed BRF mismatch of file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: true when a declared BRF record exists and differs from
/// lcov_computed_brf; false otherwise.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_brf_mismatch(d: &LcovDoc, f: Int) -> Bool {
  let decl = lcov_declared_brf(d, f);
  if decl < 0 {
    return false;
  }
  return decl != lcov_computed_brf(d, f);
}

/// Declared/computed BRH mismatch of file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: true when a declared BRH record exists and differs from
/// lcov_computed_brh; false otherwise.
/// Error case: none.
/// Complexity: O(records).
pub fn lcov_brh_mismatch(d: &LcovDoc, f: Int) -> Bool {
  let decl = lcov_declared_brh(d, f);
  if decl < 0 {
    return false;
  }
  return decl != lcov_computed_brh(d, f);
}

// --------------------------------------------------
//  Record accessors
// --------------------------------------------------

/// Number of FN records in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the record count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_fn_count(d: &LcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return 0;
  }
  let off: Int = d.fn_off[f];
  let n: Int = d.fn_n[f];
  let total = _min2(d.fn_line.len(), d.fn_name.len());
  return _span(off, n, total);
}

/// Declaration line of FN record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the line number; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_fn_line(d: &LcovDoc, f: Int, i: Int) -> Int {
  let n = lcov_fn_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.fn_off[f];
  let v: Int = d.fn_line[off + i];
  return v;
}

/// Name of FN record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the function name; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_fn_name(d: &LcovDoc, f: Int, i: Int) -> Str {
  let n = lcov_fn_count(d, f);
  if i < 0 || i >= n {
    return "";
  }
  let off: Int = d.fn_off[f];
  let v: Str = d.fn_name[off + i];
  return v;
}

/// Number of FNDA records in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the record count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_fnda_count(d: &LcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return 0;
  }
  let off: Int = d.fnda_off[f];
  let n: Int = d.fnda_n[f];
  let total = _min2(d.fnda_hits.len(), d.fnda_name.len());
  return _span(off, n, total);
}

/// Execution count of FNDA record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the count; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_fnda_hits(d: &LcovDoc, f: Int, i: Int) -> Int {
  let n = lcov_fnda_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.fnda_off[f];
  let v: Int = d.fnda_hits[off + i];
  return v;
}

/// Function name of FNDA record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the name; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_fnda_name(d: &LcovDoc, f: Int, i: Int) -> Str {
  let n = lcov_fnda_count(d, f);
  if i < 0 || i >= n {
    return "";
  }
  let off: Int = d.fnda_off[f];
  let v: Str = d.fnda_name[off + i];
  return v;
}

/// Number of DA records in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the record count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_da_count(d: &LcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return 0;
  }
  let off: Int = d.da_off[f];
  let n: Int = d.da_n[f];
  var total = d.da_line.len();
  total = _min2(total, d.da_hits.len());
  total = _min2(total, d.da_cs.len());
  total = _min2(total, d.da_checksum.len());
  return _span(off, n, total);
}

/// Line number of DA record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the line number; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_da_line(d: &LcovDoc, f: Int, i: Int) -> Int {
  let n = lcov_da_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.da_off[f];
  let v: Int = d.da_line[off + i];
  return v;
}

/// Execution count of DA record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the count; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_da_hits(d: &LcovDoc, f: Int, i: Int) -> Int {
  let n = lcov_da_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.da_off[f];
  let v: Int = d.da_hits[off + i];
  return v;
}

/// True when DA record `i` in file section `f` carried a checksum field.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: true for a three-field DA record; false when there is no
/// checksum or `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_da_has_checksum(d: &LcovDoc, f: Int, i: Int) -> Bool {
  let n = lcov_da_count(d, f);
  if i < 0 || i >= n {
    return false;
  }
  let off: Int = d.da_off[f];
  let v: Int = d.da_cs[off + i];
  return v == 1;
}

/// Checksum of DA record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the checksum text; "" when the record has no checksum or `i` is
/// out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_da_checksum(d: &LcovDoc, f: Int, i: Int) -> Str {
  if !lcov_da_has_checksum(d, f, i) {
    return "";
  }
  let off: Int = d.da_off[f];
  let v: Str = d.da_checksum[off + i];
  return v;
}

/// Number of BRDA records in file section `f`.
/// Params: d - the document; f - the zero-based file index.
/// Returns: the record count (0 when `f` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_brda_count(d: &LcovDoc, f: Int) -> Int {
  if f < 0 || f >= _file_count(d) {
    return 0;
  }
  let off: Int = d.brda_off[f];
  let n: Int = d.brda_n[f];
  var total = d.brda_line.len();
  total = _min2(total, d.brda_block.len());
  total = _min2(total, d.brda_branch.len());
  total = _min2(total, d.brda_taken.len());
  return _span(off, n, total);
}

/// Line number of BRDA record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the line number; -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_brda_line(d: &LcovDoc, f: Int, i: Int) -> Int {
  let n = lcov_brda_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.brda_off[f];
  let v: Int = d.brda_line[off + i];
  return v;
}

/// Block field of BRDA record `i` in file section `f` (verbatim).
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the block text; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_brda_block(d: &LcovDoc, f: Int, i: Int) -> Str {
  let n = lcov_brda_count(d, f);
  if i < 0 || i >= n {
    return "";
  }
  let off: Int = d.brda_off[f];
  let v: Str = d.brda_block[off + i];
  return v;
}

/// Branch field of BRDA record `i` in file section `f` (verbatim).
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the branch text; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_brda_branch(d: &LcovDoc, f: Int, i: Int) -> Str {
  let n = lcov_brda_count(d, f);
  if i < 0 || i >= n {
    return "";
  }
  let off: Int = d.brda_off[f];
  let v: Str = d.brda_branch[off + i];
  return v;
}

/// Taken field of BRDA record `i` in file section `f`.
/// Params: d - the document; f - the zero-based file index; i - the
/// zero-based record index within `f`.
/// Returns: the taken count; -1 for the "-" sentinel (block not executed)
/// and for an out-of-range `i`.
/// Error case: none.
/// Complexity: O(1).
pub fn lcov_brda_taken(d: &LcovDoc, f: Int, i: Int) -> Int {
  let n = lcov_brda_count(d, f);
  if i < 0 || i >= n {
    return -1;
  }
  let off: Int = d.brda_off[f];
  let v: Int = d.brda_taken[off + i];
  return v;
}

// --------------------------------------------------
//  Canonical emitter
// --------------------------------------------------

/// Canonical emission of a whole tracefile.
/// Params: d - the document to serialize.
/// Returns: the canonical stream, every emitted line terminated by LF. File
/// sections are written in stored order and each one in exactly this record
/// order:
///   1. "TN:<name>" when the section's test name is non-empty,
///   2. "SF:<source>",
///   3. every FN record in stored order,
///   4. every FNDA record in stored order,
///   5. "FNF:<n>" / "FNH:<n>" when the declared value is >= 0,
///   6. every DA record in stored order (checksum only when it was present),
///   7. "LF:<n>" / "LH:<n>" when the declared value is >= 0,
///   8. every BRDA record in stored order ("-" for a taken value < 0),
///   9. "BRF:<n>" / "BRH:<n>" when the declared value is >= 0,
///  10. "end_of_record".
/// Record order inside a section is canonical, not byte-identical to the
/// input: a tracefile is re-parsed after emission (see SPEC.md). An empty
/// document emits "" (no bytes).
/// Error case: none. Mismatched parallel arrays are clamped to their
/// shortest length.
/// Complexity: O(total output length).
pub fn lcov_emit(d: &LcovDoc) -> Str {
  var out = "";
  let nf = _file_count(d);
  var f = 0;
  while f < nf {
    let tn: Str = d.tn[f];
    if compare.str_compare(tn, "") != 0 {
      out = out + "TN:" + tn + "\n";
    }
    let src: Str = d.sf[f];
    out = out + "SF:" + src + "\n";

    var i = 0;
    let fn_c = lcov_fn_count(d, f);
    let fn_o: Int = d.fn_off[f];
    while i < fn_c {
      let l: Int = d.fn_line[fn_o + i];
      let nm: Str = d.fn_name[fn_o + i];
      out = out + "FN:" + int_to_string(l) + "," + nm + "\n";
      i = i + 1;
    }

    i = 0;
    let fa_c = lcov_fnda_count(d, f);
    let fa_o: Int = d.fnda_off[f];
    while i < fa_c {
      let h: Int = d.fnda_hits[fa_o + i];
      let nm: Str = d.fnda_name[fa_o + i];
      out = out + "FNDA:" + int_to_string(h) + "," + nm + "\n";
      i = i + 1;
    }

    let fnf = lcov_declared_fnf(d, f);
    if fnf >= 0 {
      out = out + "FNF:" + int_to_string(fnf) + "\n";
    }
    let fnh = lcov_declared_fnh(d, f);
    if fnh >= 0 {
      out = out + "FNH:" + int_to_string(fnh) + "\n";
    }

    i = 0;
    let da_c = lcov_da_count(d, f);
    let da_o: Int = d.da_off[f];
    while i < da_c {
      let l: Int = d.da_line[da_o + i];
      let h: Int = d.da_hits[da_o + i];
      let cs: Int = d.da_cs[da_o + i];
      let txt: Str = d.da_checksum[da_o + i];
      var ln = "DA:" + int_to_string(l) + "," + int_to_string(h);
      if cs == 1 {
        ln = ln + "," + txt;
      }
      out = out + ln + "\n";
      i = i + 1;
    }

    let lf = lcov_declared_lf(d, f);
    if lf >= 0 {
      out = out + "LF:" + int_to_string(lf) + "\n";
    }
    let lh = lcov_declared_lh(d, f);
    if lh >= 0 {
      out = out + "LH:" + int_to_string(lh) + "\n";
    }

    i = 0;
    let br_c = lcov_brda_count(d, f);
    let br_o: Int = d.brda_off[f];
    while i < br_c {
      let l: Int = d.brda_line[br_o + i];
      let blk: Str = d.brda_block[br_o + i];
      let br: Str = d.brda_branch[br_o + i];
      let tk: Int = d.brda_taken[br_o + i];
      var ts = "";
      if tk < 0 {
        ts = "-";
      } else {
        ts = int_to_string(tk);
      }
      out = out + "BRDA:" + int_to_string(l) + "," + blk + "," + br + "," + ts + "\n";
      i = i + 1;
    }

    let brf = lcov_declared_brf(d, f);
    if brf >= 0 {
      out = out + "BRF:" + int_to_string(brf) + "\n";
    }
    let brh = lcov_declared_brh(d, f);
    if brh >= 0 {
      out = out + "BRH:" + int_to_string(brh) + "\n";
    }

    out = out + "end_of_record\n";
    f = f + 1;
  }
  return out;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one LCOV tracefile.
/// Params: text - the whole tracefile, LF or CRLF terminated (a single
/// trailing CR per line is dropped). Empty and SPACE/TAB-only lines are
/// ignored; every other line must be a record of the documented subset.
/// Returns: Ok(LcovDoc) for a tracefile in the documented subset. Rules:
/// a TN record sets the test name of the next SF section; a section opens
/// with SF and closes with end_of_record (a new SF while one is open is
/// Err); data records (FN, FNDA, FNF, FNH, DA, LF, LH, BRDA, BRF, BRH) are
/// only legal inside an open section; declared/computed FNF/FNH/LF/LH/BRF/
/// BRH mismatches are tolerated, not errors.
/// Error case: Err("lcov: ...") with a 1-based line number (or the SF line
/// for a missing end_of_record). The catalog is in SPEC.md.
/// Complexity: O(input length).
pub fn lcov_parse(text: Str) -> Result[LcovDoc, Str] {
  var d = lcov_doc_new();
  var pending_tn = "";
  var open = false;
  var sf_line = 0;
  let len = text.len();
  var line_start = 0;
  var line_no = 1;
  var i = 0;
  while i <= len {
    if i == len || string.byte_at(text, i) == _LC_LF {
      var line = string.str_slice(text, line_start, i);
      let raw_len = line.len();
      if raw_len > 0 && string.byte_at(line, raw_len - 1) == _LC_CR {
        line = string.str_slice(line, 0, raw_len - 1);
      }
      if !_is_blank(line) {
        if compare.str_compare(line, "end_of_record") == 0 {
          if !open {
            return _err_doc(_err_outside(line_no));
          }
          open = false;
        } elif string.str_starts_with(line, "SF:") {
          if open {
            return _err_doc(_err_unclosed(sf_line));
          }
          let src = string.str_slice(line, 3, line.len());
          if compare.str_compare(src, "") == 0 {
            return _err_doc(_err_empty(line_no));
          }
          _file_push(&mut d, src, pending_tn);
          open = true;
          sf_line = line_no;
        } elif string.str_starts_with(line, "TN:") {
          pending_tn = string.str_slice(line, 3, line.len());
        } elif !open {
          if _is_file_record(line) {
            return _err_doc(_err_outside(line_no));
          }
          return _err_doc(_err_unknown(line_no));
        } else {
          let err = _consume_open(&mut d, line, line_no);
          if compare.str_compare(err, "") != 0 {
            return _err_doc(err);
          }
        }
      }
      line_start = i + 1;
      line_no = line_no + 1;
    }
    i = i + 1;
  }
  if open {
    return _err_doc(_err_unclosed(sf_line));
  }
  return _ok_doc(d);
}
