// XIOM -- xiom.tap: Test Anything Protocol (TAP) parser and canonical emitter
// Greenfield package: pure XIOM, no FFI, no I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A line-based parser and emitter for the documented TAP subset in SPEC.md:
//   * the version line `TAP version <N>` (first non-blank line only),
//   * the plan `1..<N>` (start must be 1; before the first test or after the
//     last one, never in the middle; at most once),
//   * flat results `ok <n> [description]` / `not ok <n> [description]` with
//     sequential numbers starting at 1,
//   * the directives `# SKIP <reason>` / `# TODO <reason>` (case-insensitive),
//   * full-line diagnostics `# ...` captured raw,
//   * blank lines, and `Bail out! <reason>` (parse stops, rest is ignored).
// YAML diagnostic blocks (`---` ... `...`) are rejected, not parsed.
//
// Model: one parsed stream is a TapDoc with flat, index-aligned parallel
// vectors because XIOM v0.61.3 cannot hold Vec[StructType]. Result i is
// described by numbers[i] (declared number), oks[i] (1 = ok, 0 = not ok),
// descriptions[i], directives[i] ("", "skip" or "todo") and reasons[i].
// Comment text is captured in diagnostics[] without its stream position; see
// tap_emit for the canonical output order.
//
// Language notes (XIOM v0.61.3): free functions only; Str equality goes
// through xiom.string.compare.str_compare (BUG 17: `==` on Str values read
// from Vec[Str] elements lowers to a pointer comparison); every Vec element
// read is bound to a typed local first; Ok/Err are constructed only in the
// leaf helpers _ok_doc/_err_doc because direct Result construction in other
// shapes miscompiles in this compiler.

module xiom.tap

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[TapDoc, Str].
fn _ok_doc(d: TapDoc) -> Result[TapDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[TapDoc, Str].
fn _err_doc(m: Str) -> Result[TapDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (all ASCII, every comparison is with a byte < 128)
// --------------------------------------------------

const _TAP_TAB: UInt8 = 9u8;
const _TAP_LF: UInt8 = 10u8;
const _TAP_CR: UInt8 = 13u8;
const _TAP_SPACE: UInt8 = 32u8;
const _TAP_HASH: UInt8 = 35u8;
const _TAP_MINUS: UInt8 = 45u8;
const _TAP_DOT: UInt8 = 46u8;
const _TAP_DIGIT_0: UInt8 = 48u8;
const _TAP_DIGIT_1: UInt8 = 49u8;
const _TAP_DIGIT_9: UInt8 = 57u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One parsed TAP stream, stored flat.
/// Result i (0-based, in stream order) is described by numbers[i] (its
/// declared test number), oks[i] (1 = ok, 0 = not ok), descriptions[i],
/// directives[i] ("" | "skip" | "todo") and reasons[i]. Those five arrays
/// are index-aligned; tap_test_count reports the shortest of them so a
/// hand-built doc can never be read out of range. diagnostics[i] is the raw
/// text of the i-th "#" comment line with the leading "#" and any following
/// whitespace removed. version is 0 when no version line was present and
/// planned is -1 when no plan line was present; bailed is true when a
/// "Bail out!" line was seen (bail_reason holds its reason, "" when absent).
pub type TapDoc = {
  version: Int;
  planned: Int;
  bailed: Bool;
  bail_reason: Str;
  numbers: Vec[Int];
  oks: Vec[Int];
  descriptions: Vec[Str];
  directives: Vec[Str];
  reasons: Vec[Str];
  diagnostics: Vec[Str];
}

// --------------------------------------------------
//  Small text helpers
// --------------------------------------------------

// Drop leading ASCII spaces and tabs from `s`.
fn _trim_left(s: Str) -> Str {
  var i = 0;
  let n = s.len();
  while i < n {
    let b = string.byte_at(s, i);
    if b != _TAP_SPACE && b != _TAP_TAB {
      break;
    }
    i = i + 1;
  }
  return string.str_slice(s, i, n);
}

// Drop trailing ASCII spaces and tabs from `s`.
fn _trim_right(s: Str) -> Str {
  var e = s.len();
  while e > 0 {
    let b = string.byte_at(s, e - 1);
    if b != _TAP_SPACE && b != _TAP_TAB {
      break;
    }
    e = e - 1;
  }
  return string.str_slice(s, 0, e);
}

// Drop leading and trailing ASCII spaces and tabs from `s`.
fn _trim_ws(s: Str) -> Str {
  return _trim_right(_trim_left(s));
}

// Parse the ASCII digit run s[from..to) into a non-negative Int.
// Returns: the value; -1 when the run is empty, carries a non-digit byte, or
// would exceed 1000000000 (overflow guard). A run of zeros yields 0.
fn _parse_digits(s: Str, from: Int, to: Int) -> Int {
  if from >= to {
    return -1;
  }
  var v = 0;
  var i = from;
  while i < to {
    let b = string.byte_at(s, i);
    if b < _TAP_DIGIT_0 || b > _TAP_DIGIT_9 {
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

// Byte index of the first ".." in `s`, or -1 when there is none.
fn _find_dotdot(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  while i + 1 < n {
    if string.byte_at(s, i) == _TAP_DOT && string.byte_at(s, i + 1) == _TAP_DOT {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Byte index of the directive '#' at or after `from`, or -1. A '#' opens a
// directive only at `from` itself or when the previous byte is a space or a
// tab, so a '#' inside a description ("issue#42") stays part of the
// description.
fn _find_directive_hash(s: Str, from: Int) -> Int {
  var i = from;
  let n = s.len();
  while i < n {
    if string.byte_at(s, i) == _TAP_HASH {
      if i == from {
        return i;
      }
      let p = string.byte_at(s, i - 1);
      if p == _TAP_SPACE || p == _TAP_TAB {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// True when `line` starts with the literal "ok" or "not ok" followed by
// whitespace or the end of the line.
fn _is_test_line(line: Str) -> Bool {
  if string.str_starts_with(line, "not ok") {
    if line.len() == 6 {
      return true;
    }
    let b = string.byte_at(line, 6);
    return b == _TAP_SPACE || b == _TAP_TAB;
  }
  if string.str_starts_with(line, "ok") {
    if line.len() == 2 {
      return true;
    }
    let b = string.byte_at(line, 2);
    return b == _TAP_SPACE || b == _TAP_TAB;
  }
  return false;
}

// True when "TAP version" in `line` is followed by whitespace or the end of
// the line, so "TAP versioning" is not a version candidate.
fn _is_version_line(line: Str) -> Bool {
  if !string.str_starts_with(line, "TAP version") {
    return false;
  }
  if line.len() == 11 {
    return true;
  }
  let b = string.byte_at(line, 11);
  return b == _TAP_SPACE || b == _TAP_TAB;
}

// Version number of a version line, or -1 when the text after "TAP version"
// is empty, non-numeric, zero or over the digit overflow guard.
fn _parse_version(line: Str) -> Int {
  let rest = _trim_ws(string.str_slice(line, 11, line.len()));
  let v = _parse_digits(rest, 0, rest.len());
  if v < 1 {
    return -1;
  }
  return v;
}

// True when the trimmed line is exactly the YAML document start "---" or end
// "..." marker of a TAP diagnostic block (which this parser rejects).
fn _is_yaml_marker(line: Str) -> Bool {
  if compare.str_compare(line, "---") == 0 {
    return true;
  }
  return compare.str_compare(line, "...") == 0;
}

// Canonical form of a directive: "skip" / "todo" for SKIP/TODO in any case,
// "" for anything else (including "").
fn _canon_directive(directive: Str) -> Str {
  let lw = string.str_lower(directive);
  if compare.str_compare(lw, "skip") == 0 {
    return "skip";
  }
  if compare.str_compare(lw, "todo") == 0 {
    return "todo";
  }
  return "";
}

// --------------------------------------------------
//  Line parsers (return "" on success, else the full error message)
// --------------------------------------------------

// Parse a plan line "1..<N>" into `d`. The caller has already established
// that the line contains "..".
fn _parse_plan_line(d: &mut TapDoc, line: Str, line_no: Int) -> Str {
  if _find_dotdot(line) != 1 || string.byte_at(line, 0) != _TAP_DIGIT_1 {
    return "tap: bad plan at " + int_to_string(line_no);
  }
  let tail = string.str_slice(line, 3, line.len());
  let count = _parse_digits(tail, 0, tail.len());
  if count < 0 {
    return "tap: bad plan at " + int_to_string(line_no);
  }
  d.planned = count;
  return "";
}

// Parse one test result line into `d`, appending to all five parallel test
// arrays. The caller has already established that the line is a test line.
fn _parse_test_line(d: &mut TapDoc, line: Str, line_no: Int) -> Str {
  var is_ok = true;
  var at = 0;
  if string.str_starts_with(line, "not ok") {
    is_ok = false;
    at = 6;
  } else {
    at = 2;
  }

  let n = line.len();
  var i = at;
  while i < n {
    let b = string.byte_at(line, i);
    if b != _TAP_SPACE && b != _TAP_TAB {
      break;
    }
    i = i + 1;
  }

  if i < n && string.byte_at(line, i) == _TAP_MINUS {
    return "tap: negative test number at " + int_to_string(line_no);
  }

  var j = i;
  while j < n {
    let b = string.byte_at(line, j);
    if b < _TAP_DIGIT_0 || b > _TAP_DIGIT_9 {
      break;
    }
    j = j + 1;
  }
  if j == i {
    return "tap: bad test line at " + int_to_string(line_no);
  }
  if j < n {
    let b = string.byte_at(line, j);
    if b != _TAP_SPACE && b != _TAP_TAB {
      return "tap: bad test line at " + int_to_string(line_no);
    }
  }
  let number = _parse_digits(line, i, j);
  if number < 0 {
    return "tap: bad test line at " + int_to_string(line_no);
  }
  let expected = d.numbers.len() + 1;
  if number != expected {
    return "tap: non-sequential test number at " + int_to_string(line_no)
      + ": got " + int_to_string(number) + ", expected " + int_to_string(expected);
  }

  var k = j;
  while k < n {
    let b = string.byte_at(line, k);
    if b != _TAP_SPACE && b != _TAP_TAB {
      break;
    }
    k = k + 1;
  }

  var desc = "";
  var dir = "";
  var reason = "";
  let h = _find_directive_hash(line, k);
  if h < 0 {
    desc = _trim_right(string.str_slice(line, k, n));
  } else {
    desc = _trim_right(string.str_slice(line, k, h));
    var m = h + 1;
    while m < n {
      let b = string.byte_at(line, m);
      if b != _TAP_SPACE && b != _TAP_TAB {
        break;
      }
      m = m + 1;
    }
    var e = m;
    while e < n {
      let b = string.byte_at(line, e);
      if b == _TAP_SPACE || b == _TAP_TAB {
        break;
      }
      e = e + 1;
    }
    let word = string.str_slice(line, m, e);
    let lw = string.str_lower(word);
    if compare.str_compare(lw, "skip") == 0 {
      dir = "skip";
    } elif compare.str_compare(lw, "todo") == 0 {
      dir = "todo";
    } else {
      return "tap: bad directive at " + int_to_string(line_no);
    }
    var r = e;
    while r < n {
      let b = string.byte_at(line, r);
      if b != _TAP_SPACE && b != _TAP_TAB {
        break;
      }
      r = r + 1;
    }
    reason = _trim_right(string.str_slice(line, r, n));
  }

  d.numbers.push(number);
  if is_ok {
    d.oks.push(1);
  } else {
    d.oks.push(0);
  }
  d.descriptions.push(desc);
  d.directives.push(dir);
  d.reasons.push(reason);
  return "";
}

// --------------------------------------------------
//  Construction
// --------------------------------------------------

/// A fresh, empty document: no version (0), no plan (-1), no results, no
/// diagnostics and no bail out.
/// Params: none.
/// Returns: an empty TapDoc.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_doc_new() -> TapDoc {
  return TapDoc{
    version: 0;
    planned: -1;
    bailed: false;
    bail_reason: "";
    numbers: Vec[Int].new();
    oks: Vec[Int].new();
    descriptions: Vec[Str].new();
    directives: Vec[Str].new();
    reasons: Vec[Str].new();
    diagnostics: Vec[Str].new();
  };
}

/// Append one test result to `d`, numbering it with the next free number
/// (current result count + 1). `oks` stores 1 for ok and 0 for not ok.
/// Params: d - the document to mutate; ok - the verdict; description - the
/// description (stored verbatim; the emitter trims it); directive - "" or a
/// SKIP/TODO keyword in any case; reason - the directive reason.
/// Returns: nothing.
/// Error case: none. A directive that is neither SKIP nor TODO is stored
/// verbatim (see tap_emit) and an empty directive drops `reason`.
/// Complexity: O(1).
pub fn tap_add_test(d: &mut TapDoc, ok: Bool, description: Str, directive: Str, reason: Str) {
  let number = d.numbers.len() + 1;
  d.numbers.push(number);
  if ok {
    d.oks.push(1);
  } else {
    d.oks.push(0);
  }
  d.descriptions.push(description);
  let canon = _canon_directive(directive);
  if canon.len() > 0 {
    d.directives.push(canon);
    d.reasons.push(reason);
  } else {
    d.directives.push(directive);
    d.reasons.push("");
  }
}

/// Record a version number on `d`; values <= 0 clear it (0 = no version).
/// Params: d - the document to mutate; n - the TAP version number.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_set_version(d: &mut TapDoc, n: Int) {
  d.version = n;
}

/// Record the plan count on `d`; a negative value clears it (-1 = no plan).
/// Params: d - the document to mutate; n - the planned number of tests.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_set_plan(d: &mut TapDoc, n: Int) {
  d.planned = n;
}

/// Mark `d` as bailed out with `reason` (there is no way to unset it).
/// Params: d - the document to mutate; reason - the bail reason text.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_set_bail(d: &mut TapDoc, reason: Str) {
  d.bailed = true;
  d.bail_reason = reason;
}

/// Append one diagnostic line to `d`, without the leading "#".
/// Params: d - the document to mutate; text - the diagnostic text.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_add_diagnostic(d: &mut TapDoc, text: Str) {
  d.diagnostics.push(text);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

// Number of index-aligned test entries: the shortest of the five parallel
// test arrays, so a hand-built doc can never be read out of range.
fn _test_count(d: &TapDoc) -> Int {
  var n = d.numbers.len();
  if d.oks.len() < n {
    n = d.oks.len();
  }
  if d.descriptions.len() < n {
    n = d.descriptions.len();
  }
  if d.directives.len() < n {
    n = d.directives.len();
  }
  if d.reasons.len() < n {
    n = d.reasons.len();
  }
  return n;
}

/// Version number recorded by the "TAP version <N>" line.
/// Params: d - the document.
/// Returns: the version; 0 when the stream had no version line.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_version(d: &TapDoc) -> Int {
  let v: Int = d.version;
  return v;
}

/// Planned number of tests from the "1..<N>" line.
/// Params: d - the document.
/// Returns: the plan count (0 for a "1..0" plan); -1 when there is no plan.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_planned(d: &TapDoc) -> Int {
  let v: Int = d.planned;
  return v;
}

/// Number of test results stored in `d`.
/// Params: d - the document.
/// Returns: the number of index-aligned results (see the TapDoc doc comment).
/// Error case: none.
/// Complexity: O(1).
pub fn tap_test_count(d: &TapDoc) -> Int {
  return _test_count(d);
}

/// Declared number of test result `i`.
/// Params: d - the document; i - the zero-based result index.
/// Returns: the number; -1 when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_number(d: &TapDoc, i: Int) -> Int {
  if i < 0 || i >= _test_count(d) {
    return -1;
  }
  let v: Int = d.numbers[i];
  return v;
}

/// Verdict of test result `i`.
/// Params: d - the document; i - the zero-based result index.
/// Returns: true when the result was "ok"; false for "not ok" or when `i` is
/// out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_is_ok(d: &TapDoc, i: Int) -> Bool {
  if i < 0 || i >= _test_count(d) {
    return false;
  }
  let v: Int = d.oks[i];
  return v == 1;
}

/// Description of test result `i`.
/// Params: d - the document; i - the zero-based result index.
/// Returns: the description ("" for none); "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_description(d: &TapDoc, i: Int) -> Str {
  if i < 0 || i >= _test_count(d) {
    return "";
  }
  let v: Str = d.descriptions[i];
  return v;
}

/// Directive kind of test result `i`.
/// Params: d - the document; i - the zero-based result index.
/// Returns: "skip", "todo" or "" (no directive); "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_directive(d: &TapDoc, i: Int) -> Str {
  if i < 0 || i >= _test_count(d) {
    return "";
  }
  let v: Str = d.directives[i];
  return v;
}

/// Directive reason of test result `i`.
/// Params: d - the document; i - the zero-based result index.
/// Returns: the reason ("" when absent); "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_reason(d: &TapDoc, i: Int) -> Str {
  if i < 0 || i >= _test_count(d) {
    return "";
  }
  let v: Str = d.reasons[i];
  return v;
}

/// Number of results that passed: "ok" with no directive.
/// Params: d - the document.
/// Returns: the count. A result with a SKIP or TODO directive is not counted
/// here even when it is an "ok" (see tap_skipped / tap_todo).
/// Error case: none.
/// Complexity: O(results).
pub fn tap_passed(d: &TapDoc) -> Int {
  var c = 0;
  var i = 0;
  let n = _test_count(d);
  while i < n {
    let okv: Int = d.oks[i];
    let dir: Str = d.directives[i];
    if okv == 1 && dir.len() == 0 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Number of results that failed: "not ok" with no directive.
/// Params: d - the document.
/// Returns: the count. A failing TODO is not counted here (see tap_todo).
/// Error case: none.
/// Complexity: O(results).
pub fn tap_failed(d: &TapDoc) -> Int {
  var c = 0;
  var i = 0;
  let n = _test_count(d);
  while i < n {
    let okv: Int = d.oks[i];
    let dir: Str = d.directives[i];
    if okv == 0 && dir.len() == 0 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Number of results carrying a SKIP directive (ok or not ok).
/// Params: d - the document.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(results).
pub fn tap_skipped(d: &TapDoc) -> Int {
  var c = 0;
  var i = 0;
  let n = _test_count(d);
  while i < n {
    let dir: Str = d.directives[i];
    if compare.str_compare(dir, "skip") == 0 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Number of results carrying a TODO directive (ok or not ok). A passing
/// TODO is an unexpected success and is still counted here, not in
/// tap_passed.
/// Params: d - the document.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(results).
pub fn tap_todo(d: &TapDoc) -> Int {
  var c = 0;
  var i = 0;
  let n = _test_count(d);
  while i < n {
    let dir: Str = d.directives[i];
    if compare.str_compare(dir, "todo") == 0 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// True when the stream contained a "Bail out!" line.
/// Params: d - the document.
/// Returns: the bail flag.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_bailed(d: &TapDoc) -> Bool {
  let v: Bool = d.bailed;
  return v;
}

/// Reason text of the "Bail out!" line.
/// Params: d - the document.
/// Returns: the reason ("" when the line was bare or there was no bail out).
/// Error case: none.
/// Complexity: O(1).
pub fn tap_bail_reason(d: &TapDoc) -> Str {
  let v: Str = d.bail_reason;
  return v;
}

/// Number of diagnostic ("#") lines stored in `d`.
/// Params: d - the document.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_diagnostic_count(d: &TapDoc) -> Int {
  let n: Int = d.diagnostics.len();
  return n;
}

/// Text of diagnostic line `i`, with the leading "#" and whitespace removed.
/// Params: d - the document; i - the zero-based diagnostic index.
/// Returns: the text; "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_diagnostic(d: &TapDoc, i: Int) -> Str {
  if i < 0 || i >= d.diagnostics.len() {
    return "";
  }
  let v: Str = d.diagnostics[i];
  return v;
}

// --------------------------------------------------
//  Canonical line writers
// --------------------------------------------------

/// Canonical "TAP version <n>" line.
/// Params: n - the version number.
/// Returns: the line without a terminator; "" when n <= 0 (no version line).
/// Error case: none.
/// Complexity: O(1).
pub fn tap_write_version(n: Int) -> Str {
  if n <= 0 {
    return "";
  }
  return "TAP version " + int_to_string(n);
}

/// Canonical plan line "1..<n>".
/// Params: n - the planned number of tests.
/// Returns: the line without a terminator; "" when n < 0 (no plan line).
/// Error case: none.
/// Complexity: O(1).
pub fn tap_write_plan(n: Int) -> Str {
  if n < 0 {
    return "";
  }
  return "1.." + int_to_string(n);
}

/// Canonical test result line.
/// Params: number - the declared test number (emitted verbatim, not
/// validated); ok - the verdict; description - the description (trimmed;
/// omitted when empty); directive - "" or a SKIP/TODO keyword in any case;
/// reason - the directive reason (trimmed; omitted when empty).
/// Returns: e.g. "ok 1 checks things", "not ok 2 broke # TODO fix it",
/// "ok 3 later # SKIP not ready". A directive that matches neither SKIP nor
/// TODO is emitted verbatim after "#", so the line may not re-parse.
/// Error case: none.
/// Complexity: O(1).
pub fn tap_write_test(number: Int, ok: Bool, description: Str, directive: Str, reason: Str) -> Str {
  var out = "ok ";
  if !ok {
    out = "not ok ";
  }
  out = out + int_to_string(number);
  let desc = _trim_ws(description);
  if desc.len() > 0 {
    out = out + " " + desc;
  }
  let canon = _canon_directive(directive);
  let rsn = _trim_ws(reason);
  if canon.len() > 0 {
    out = out + " # " + string.str_upper(canon);
    if rsn.len() > 0 {
      out = out + " " + rsn;
    }
  } elif directive.len() > 0 {
    out = out + " # " + directive;
    if rsn.len() > 0 {
      out = out + " " + rsn;
    }
  }
  return out;
}

/// Canonical diagnostic line.
/// Params: text - the diagnostic text without a leading "#".
/// Returns: "#" for an empty text, else "# <text>" (no terminator).
/// Error case: none.
/// Complexity: O(1).
pub fn tap_write_comment(text: Str) -> Str {
  if text.len() == 0 {
    return "#";
  }
  return "# " + text;
}

/// Canonical "Bail out!" line.
/// Params: reason - the bail reason (trimmed; omitted when empty).
/// Returns: "Bail out!" or "Bail out! <reason>" (no terminator).
/// Error case: none.
/// Complexity: O(1).
pub fn tap_write_bail(reason: Str) -> Str {
  let r = _trim_ws(reason);
  if r.len() == 0 {
    return "Bail out!";
  }
  return "Bail out! " + r;
}

/// Canonical emission of a whole document.
/// Params: d - the document to serialize.
/// Returns: the canonical stream, every emitted line terminated by LF:
///   * "TAP version <N>" when tap_version > 0,
///   * every diagnostic ("# ...") in stored order,
///   * "1..<N>" when tap_planned >= 0,
///   * every result in stored order, and
///   * "Bail out! <reason>" when bailed.
/// The plan is always written before the results, even when it was parsed
/// from the end of the stream, and diagnostics lose their original position;
/// both are canonical replays, not byte-identical reproductions (SPEC.md).
/// An empty document emits "".
/// Error case: none. Mismatched parallel arrays are clamped to their
/// shortest length.
/// Complexity: O(total output length).
pub fn tap_emit(d: &TapDoc) -> Str {
  var out = "";
  let ver = tap_version(d);
  if ver > 0 {
    out = out + tap_write_version(ver) + "\n";
  }
  var i = 0;
  let dn = tap_diagnostic_count(d);
  while i < dn {
    let s: Str = d.diagnostics[i];
    out = out + tap_write_comment(s) + "\n";
    i = i + 1;
  }
  let plan = tap_planned(d);
  if plan >= 0 {
    out = out + tap_write_plan(plan) + "\n";
  }
  i = 0;
  let n = _test_count(d);
  while i < n {
    let num: Int = d.numbers[i];
    let okv: Int = d.oks[i];
    let desc: Str = d.descriptions[i];
    let dir: Str = d.directives[i];
    let rsn: Str = d.reasons[i];
    out = out + tap_write_test(num, okv == 1, desc, dir, rsn) + "\n";
    i = i + 1;
  }
  if tap_bailed(d) {
    out = out + tap_write_bail(tap_bail_reason(d)) + "\n";
  }
  return out;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one TAP stream.
/// Params: text - the whole document, LF or CRLF terminated (a single
/// trailing CR per line is dropped). Leading and trailing ASCII spaces/tabs
/// of every line are ignored.
/// Returns: Ok(TapDoc) for a stream in the documented subset. The version
/// line must be the first non-blank line; the plan "1..<N>" (start 1) may
/// appear once, before the first result or after the last one; test numbers
/// must be 1, 2, 3, ... in stream order; a "Bail out!" line stops the parse
/// and everything after it is ignored. The plan count is not checked against
/// the number of results.
/// Error case: Err("tap: ...") with a 1-based line number for a bad or
/// misplaced version line, a bad/duplicate/mid-stream plan, a malformed test
/// line, a negative or non-sequential test number, a bad directive, a YAML
/// diagnostic block, unrecognized text before the plan or an unrecognized
/// line after it. The catalog is in SPEC.md.
/// Complexity: O(input length).
pub fn tap_parse(text: Str) -> Result[TapDoc, Str] {
  var doc = tap_doc_new();
  let len = text.len();
  var line_start = 0;
  var line_no = 1;
  var content_seen = false;
  var plan_seen = false;
  var plan_line = 0;
  var plan_after_tests = false;
  var i = 0;
  while i <= len {
    if i == len || string.byte_at(text, i) == _TAP_LF {
      var line = string.str_slice(text, line_start, i);
      let raw_len = line.len();
      if raw_len > 0 && string.byte_at(line, raw_len - 1) == _TAP_CR {
        line = string.str_slice(line, 0, raw_len - 1);
      }
      let trimmed = _trim_ws(line);
      if trimmed.len() > 0 {
        if string.str_starts_with(trimmed, "Bail out!") {
          let reason = _trim_left(string.str_slice(trimmed, 9, trimmed.len()));
          doc.bailed = true;
          doc.bail_reason = reason;
          return _ok_doc(doc);
        } elif _is_version_line(trimmed) {
          if content_seen {
            return _err_doc("tap: misplaced version line at " + int_to_string(line_no));
          }
          let ver = _parse_version(trimmed);
          if ver < 1 {
            return _err_doc("tap: bad version line at " + int_to_string(line_no));
          }
          doc.version = ver;
          content_seen = true;
        } elif string.byte_at(trimmed, 0) == _TAP_HASH {
          let diag = _trim_left(string.str_slice(trimmed, 1, trimmed.len()));
          doc.diagnostics.push(diag);
          content_seen = true;
        } elif _is_test_line(trimmed) {
          if plan_after_tests {
            return _err_doc("tap: plan after tests at " + int_to_string(plan_line));
          }
          let err = _parse_test_line(&mut doc, trimmed, line_no);
          if err.len() > 0 {
            return _err_doc(err);
          }
          content_seen = true;
        } elif _is_yaml_marker(trimmed) {
          return _err_doc("tap: yaml diagnostics unsupported at " + int_to_string(line_no));
        } elif _find_dotdot(trimmed) >= 0 {
          if plan_seen {
            return _err_doc("tap: duplicate plan at " + int_to_string(line_no));
          }
          let err = _parse_plan_line(&mut doc, trimmed, line_no);
          if err.len() > 0 {
            return _err_doc(err);
          }
          plan_seen = true;
          plan_line = line_no;
          if doc.numbers.len() > 0 {
            plan_after_tests = true;
          }
          content_seen = true;
        } else {
          if plan_seen {
            return _err_doc("tap: unrecognized line at " + int_to_string(line_no));
          }
          return _err_doc("tap: text before plan at " + int_to_string(line_no));
        }
      }
      line_start = i + 1;
      line_no = line_no + 1;
    }
    i = i + 1;
  }
  return _ok_doc(doc);
}
