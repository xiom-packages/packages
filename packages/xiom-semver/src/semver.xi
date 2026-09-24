// XIOM -- xiom.semver: strict Semantic Versioning 2.0 parsing, precedence and
// single-comparator range satisfaction.
// Port task: greenfield pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a version is a five-field struct. `pre` and `build` are "" when
// absent; `pre` keeps the raw dotted identifier list ("alpha.1"), as does
// `build`. semver_parse is strict SemVer 2.0: exactly three numeric
// components, no leading zeros (except "0"), pre-release/build identifiers
// drawn from [0-9A-Za-z-], no empty identifiers, and no leading zeros in
// numeric pre-release identifiers.
//
// Comparison follows SemVer 2.0 section 11: the numeric triple first, then
// pre-release (absent > present) with identifiers compared left to right
// (numeric numerically, alphanumeric byte-wise, numeric < alphanumeric, a
// shorter list that is a prefix sorts first). Build metadata is ignored.
//
// Ranges are single comparators: "*" or [= > >= < <= ^ ~] OPERAND where
// OPERAND is MAJOR[.MINOR[.PATCH]] with an optional -pre / +build suffix and
// missing components zero-padded. Callers combine several ranges by passing a
// list to semver_satisfies_any.

module xiom.semver

use xiom.string;
use xiom.string.compare;
use xiom.convert;

const _SEMVER_DOT: UInt8 = 46u8;
const _SEMVER_HYPHEN: UInt8 = 45u8;
const _SEMVER_PLUS: UInt8 = 43u8;
const _SEMVER_ZERO: UInt8 = 48u8;
const _SEMVER_NINE: UInt8 = 57u8;
const _SEMVER_UPPER_A: UInt8 = 65u8;
const _SEMVER_UPPER_Z: UInt8 = 90u8;
const _SEMVER_LOWER_A: UInt8 = 97u8;
const _SEMVER_LOWER_Z: UInt8 = 122u8;
const _SEMVER_CARET: UInt8 = 94u8;
const _SEMVER_TILDE: UInt8 = 126u8;
const _SEMVER_EQUALS: UInt8 = 61u8;
const _SEMVER_GREATER: UInt8 = 62u8;
const _SEMVER_LESS: UInt8 = 60u8;

const _SEMVER_OP_EXACT: Int = 0;
const _SEMVER_OP_GT: Int = 1;
const _SEMVER_OP_GE: Int = 2;
const _SEMVER_OP_LT: Int = 3;
const _SEMVER_OP_LE: Int = 4;
const _SEMVER_OP_CARET: Int = 5;
const _SEMVER_OP_TILDE: Int = 6;

const _SEMVER_INT_MAX_DIV10: Int = 922337203685477580;
const _SEMVER_INT_MAX_LAST: Int = 7;

/// Parsed semantic version. `major` / `minor` / `patch` are the numeric
/// components; `pre` and `build` are the raw dotted identifier lists and are
/// "" when the version carries none.
pub type SemVer = {
  major: Int;
  minor: Int;
  patch: Int;
  pre: Str;
  build: Str;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _semver_ok(v: SemVer) -> Result[SemVer, Str] { return Ok(v); }
fn _semver_err(m: Str) -> Result[SemVer, Str] { return Err(m); }
fn _bool_ok(b: Bool) -> Result[Bool, Str] { return Ok(b); }
fn _bool_err(m: Str) -> Result[Bool, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Byte predicates and scanning
// ---------------------------------------------------------------------------

fn _is_digit(b: UInt8) -> Bool {
  return b >= _SEMVER_ZERO && b <= _SEMVER_NINE;
}

fn _is_alpha(b: UInt8) -> Bool {
  if b >= _SEMVER_LOWER_A && b <= _SEMVER_LOWER_Z { return true; }
  if b >= _SEMVER_UPPER_A && b <= _SEMVER_UPPER_Z { return true; }
  return false;
}

// Identifier byte: ASCII alphanumeric or hyphen.
fn _is_id_byte(b: UInt8) -> Bool {
  if _is_digit(b) { return true; }
  if _is_alpha(b) { return true; }
  return b == _SEMVER_HYPHEN;
}

// End of the ASCII digit run starting at `start`.
fn _digits_end(s: Str, start: Int) -> Int {
  var i = start;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if !_is_digit(b) { break; }
    i = i + 1;
  }
  return i;
}

// True when [start, end) is a multi-digit run beginning with '0'.
fn _leading_zero(s: Str, start: Int, end: Int) -> Bool {
  if end - start <= 1 { return false; }
  return string.byte_at(s, start) == _SEMVER_ZERO;
}

// True when every byte of s is an ASCII digit; "" is not all digits.
fn _all_digits(s: Str) -> Bool {
  if s.len() == 0 { return false; }
  var i = 0;
  while i < s.len() {
    if !_is_digit(string.byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Identifier-list validation
// ---------------------------------------------------------------------------

// "" when `part` is a valid dot-separated pre-release list, else a
// "semver: ..." error message naming `full` (the whole version text).
// Numeric identifiers must not carry leading zeros.
fn _pre_ident_error(part: Str, full: Str) -> Str {
  let n = part.len();
  if n == 0 { return "semver: empty pre-release identifier: " + full; }
  var start = 0;
  var i = 0;
  while i <= n {
    if i == n || string.byte_at(part, i) == _SEMVER_DOT {
      if i == start { return "semver: empty pre-release identifier: " + full; }
      var all_digits = true;
      var j = start;
      while j < i {
        let b = string.byte_at(part, j);
        if !_is_id_byte(b) { return "semver: malformed pre-release: " + full; }
        if !_is_digit(b) { all_digits = false; }
        j = j + 1;
      }
      if all_digits && i - start > 1 && string.byte_at(part, start) == _SEMVER_ZERO {
        return "semver: leading zero in pre-release identifier: " + full;
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return "";
}

// "" when `part` is a valid dot-separated build list (leading zeros allowed),
// else a "semver: ..." error message naming `full`.
fn _build_ident_error(part: Str, full: Str) -> Str {
  let n = part.len();
  if n == 0 { return "semver: empty build identifier: " + full; }
  var start = 0;
  var i = 0;
  while i <= n {
    if i == n || string.byte_at(part, i) == _SEMVER_DOT {
      if i == start { return "semver: empty build identifier: " + full; }
      var j = start;
      while j < i {
        if !_is_id_byte(string.byte_at(part, j)) { return "semver: malformed build: " + full; }
        j = j + 1;
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return "";
}

// ---------------------------------------------------------------------------
// Numeric components
// ---------------------------------------------------------------------------

// True when the digit run [start, end) would not fit a signed 64-bit Int.
fn _num_overflow(s: Str, start: Int, end: Int) -> Bool {
  var acc = 0;
  var i = start;
  while i < end {
    let d = (string.byte_at(s, i) as Int) - 48;
    if acc > _SEMVER_INT_MAX_DIV10 { return true; }
    if acc == _SEMVER_INT_MAX_DIV10 && d > _SEMVER_INT_MAX_LAST { return true; }
    acc = acc * 10 + d;
    i = i + 1;
  }
  return false;
}

// Value of a validated digit run [start, end) that fits a signed 64-bit Int.
fn _num_value(s: Str, start: Int, end: Int) -> Int {
  var acc = 0;
  var i = start;
  while i < end {
    acc = acc * 10 + ((string.byte_at(s, i) as Int) - 48);
    i = i + 1;
  }
  return acc;
}

// Number of dot-separated numeric components written before any -pre/+build
// suffix: 1 for "1", 2 for "1.2", 3 for "1.2.3-rc.1".
fn _specified_components(s: Str) -> Int {
  var count = 1;
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _SEMVER_HYPHEN || b == _SEMVER_PLUS { break; }
    if b == _SEMVER_DOT { count = count + 1; }
    i = i + 1;
  }
  return count;
}

// ---------------------------------------------------------------------------
// Version parsing
// ---------------------------------------------------------------------------

// Core parser. allow_partial=false requires MAJOR.MINOR.PATCH;
// allow_partial=true accepts MAJOR or MAJOR.MINOR and zero-pads the missing
// components (range operands).
fn _version_parse(s: Str, allow_partial: Bool) -> Result[SemVer, Str] {
  let n = s.len();
  if n == 0 { return _semver_err("semver: empty input"); }

  let maj_end = _digits_end(s, 0);
  if maj_end == 0 { return _semver_err("semver: malformed version: " + s); }
  if _leading_zero(s, 0, maj_end) { return _semver_err("semver: leading zero in major: " + s); }
  if _num_overflow(s, 0, maj_end) { return _semver_err("semver: number too large: " + s); }

  var has_minor = false;
  var has_patch = false;
  var min_start = 0;
  var min_end = 0;
  var pat_start = 0;
  var pat_end = 0;
  var i = maj_end;

  if i < n && string.byte_at(s, i) == _SEMVER_DOT {
    min_start = i + 1;
    min_end = _digits_end(s, min_start);
    if min_end == min_start { return _semver_err("semver: missing minor: " + s); }
    if _leading_zero(s, min_start, min_end) { return _semver_err("semver: leading zero in minor: " + s); }
    if _num_overflow(s, min_start, min_end) { return _semver_err("semver: number too large: " + s); }
    has_minor = true;
    i = min_end;
    if i < n && string.byte_at(s, i) == _SEMVER_DOT {
      pat_start = i + 1;
      pat_end = _digits_end(s, pat_start);
      if pat_end == pat_start { return _semver_err("semver: missing patch: " + s); }
      if _leading_zero(s, pat_start, pat_end) { return _semver_err("semver: leading zero in patch: " + s); }
      if _num_overflow(s, pat_start, pat_end) { return _semver_err("semver: number too large: " + s); }
      has_patch = true;
      i = pat_end;
    } elif !allow_partial {
      return _semver_err("semver: missing patch: " + s);
    }
  } elif !allow_partial {
    return _semver_err("semver: missing minor: " + s);
  }

  var pre = "";
  var build = "";
  if i < n {
    let c = string.byte_at(s, i);
    if c == _SEMVER_HYPHEN {
      let pre_start = i + 1;
      var pre_end = n;
      var k = pre_start;
      while k < n {
        if string.byte_at(s, k) == _SEMVER_PLUS { pre_end = k; break; }
        k = k + 1;
      }
      pre = string.str_slice(s, pre_start, pre_end);
      let perr = _pre_ident_error(pre, s);
      if perr.len() > 0 { return _semver_err(perr); }
      if pre_end < n {
        build = string.str_slice(s, pre_end + 1, n);
        let berr = _build_ident_error(build, s);
        if berr.len() > 0 { return _semver_err(berr); }
      }
    } elif c == _SEMVER_PLUS {
      build = string.str_slice(s, i + 1, n);
      let berr = _build_ident_error(build, s);
      if berr.len() > 0 { return _semver_err(berr); }
    } else {
      return _semver_err("semver: malformed version: " + s);
    }
  }

  let major = _num_value(s, 0, maj_end);
  var minor = 0;
  if has_minor { minor = _num_value(s, min_start, min_end); }
  var patch = 0;
  if has_patch { patch = _num_value(s, pat_start, pat_end); }

  let v = SemVer{ major: major; minor: minor; patch: patch; pre: pre; build: build };
  return _semver_ok(v);
}

/// Parse a strict SemVer 2.0 version string.
/// Params: s - MAJOR.MINOR.PATCH with optional -pre-release and +build.
/// Returns: Ok(SemVer) for a strict version; Err("semver: ...") otherwise
/// (see SPEC.md for the message catalog).
/// Examples: "1.2.3" parses as 1/2/3; "1.0.0-alpha.1+7" keeps pre "alpha.1"
/// and build "7".
/// Complexity: O(len(s)).
pub fn semver_parse(s: Str) -> Result[SemVer, Str] {
  return _version_parse(s, false);
}

/// Render a version as its canonical string.
/// Params: v - the version.
/// Returns: MAJOR.MINOR.PATCH, then "-pre" when pre is non-empty, then
/// "+build" when build is non-empty.
/// Error case: none.
/// Complexity: O(digits + len(pre) + len(build)).
pub fn semver_format(v: &SemVer) -> Str {
  var out = convert.int_to_string(v.major) + "." + convert.int_to_string(v.minor) + "." + convert.int_to_string(v.patch);
  if v.pre.len() > 0 { out = out + "-" + v.pre; }
  if v.build.len() > 0 { out = out + "+" + v.build; }
  return out;
}

// Normalize an arbitrary sign to -1/0/1.
fn _norm(c: Int) -> Int {
  if c < 0 { return -1; }
  if c > 0 { return 1; }
  return 0;
}

// Compare numeric pre-release identifiers of any length: no leading zeros, so
// more digits is larger and equal lengths compare byte-wise.
fn _compare_numeric(a: Str, b: Str) -> Int {
  let la = a.len();
  let lb = b.len();
  if la != lb {
    if la < lb { return -1; }
    return 1;
  }
  return _norm(compare.str_compare(a, b));
}

// Compare one pre-release identifier: numeric numerically, alphanumeric
// byte-wise, numeric before alphanumeric.
fn _compare_ident(a: Str, b: Str) -> Int {
  let a_num = _all_digits(a);
  let b_num = _all_digits(b);
  if a_num && b_num { return _compare_numeric(a, b); }
  if a_num { return -1; }
  if b_num { return 1; }
  return _norm(compare.str_compare(a, b));
}

// Compare two raw pre-release lists identifier by identifier; a list that is
// a prefix of the other sorts first.
fn _compare_pre(a: Str, b: Str) -> Int {
  let an = a.len();
  let bn = b.len();
  var i = 0;
  var j = 0;
  loop {
    var a_end = i;
    while a_end < an && string.byte_at(a, a_end) != _SEMVER_DOT { a_end = a_end + 1; }
    var b_end = j;
    while b_end < bn && string.byte_at(b, b_end) != _SEMVER_DOT { b_end = b_end + 1; }
    let ai = string.str_slice(a, i, a_end);
    let bi = string.str_slice(b, j, b_end);
    let c = _compare_ident(ai, bi);
    if c != 0 { return c; }
    let a_last = a_end >= an;
    let b_last = b_end >= bn;
    if a_last && b_last { return 0; }
    if a_last { return -1; }
    if b_last { return 1; }
    i = a_end + 1;
    j = b_end + 1;
  }
}

/// Compare two versions by SemVer 2.0 precedence.
/// Params: a, b - the versions.
/// Returns: -1 when a < b, 0 when equal, 1 when a > b. The numeric triple is
/// compared first; then a release outranks a pre-release; then pre-release
/// identifiers are compared left to right. Build metadata is ignored.
/// Error case: none.
/// Complexity: O(digits + len(pre)).
pub fn semver_compare(a: &SemVer, b: &SemVer) -> Int {
  if a.major != b.major {
    if a.major < b.major { return -1; }
    return 1;
  }
  if a.minor != b.minor {
    if a.minor < b.minor { return -1; }
    return 1;
  }
  if a.patch != b.patch {
    if a.patch < b.patch { return -1; }
    return 1;
  }
  let ap = a.pre.len() > 0;
  let bp = b.pre.len() > 0;
  if !ap && !bp { return 0; }
  if !ap { return 1; }
  if !bp { return -1; }
  return _compare_pre(a.pre, b.pre);
}

/// True when the version carries a pre-release part (`pre` is non-empty).
/// Error case: none.
/// Complexity: O(1).
pub fn semver_is_prerelease(v: &SemVer) -> Bool {
  return v.pre.len() > 0;
}

// ---------------------------------------------------------------------------
// Ranges
// ---------------------------------------------------------------------------

// Upper bound of a caret range: <major+1>.0.0 when major > 0; with a zero
// major the bound depends on how many components were written:
// ^0.x -> <1.0.0; ^0.0 -> <0.1.0; ^0.0.z -> <0.0.z+1.
fn _caret_upper(b: &SemVer, specified: Int) -> SemVer {
  if b.major > 0 {
    return SemVer{ major: b.major + 1; minor: 0; patch: 0; pre: ""; build: "" };
  }
  if specified < 2 {
    return SemVer{ major: 1; minor: 0; patch: 0; pre: ""; build: "" };
  }
  if b.minor > 0 {
    return SemVer{ major: 0; minor: b.minor + 1; patch: 0; pre: ""; build: "" };
  }
  if specified >= 3 {
    return SemVer{ major: 0; minor: 0; patch: b.patch + 1; pre: ""; build: "" };
  }
  return SemVer{ major: 0; minor: 1; patch: 0; pre: ""; build: "" };
}

// Tilde upper bound: <major>.<minor+1>.0 when minor was written, else
// <major+1>.0.0.
fn _tilde_upper(b: &SemVer, specified: Int) -> SemVer {
  if specified >= 2 {
    return SemVer{ major: b.major; minor: b.minor + 1; patch: 0; pre: ""; build: "" };
  }
  return SemVer{ major: b.major + 1; minor: 0; patch: 0; pre: ""; build: "" };
}

// True when v lies in the range denoted by comparator `op` and bound `b`;
// `specified` is the number of numeric components written in the operand.
fn _range_check(v: &SemVer, b: SemVer, op: Int, specified: Int) -> Bool {
  let cmp = semver_compare(v, &b);
  if op == _SEMVER_OP_EXACT { return cmp == 0; }
  if op == _SEMVER_OP_GT { return cmp > 0; }
  if op == _SEMVER_OP_GE { return cmp >= 0; }
  if op == _SEMVER_OP_LT { return cmp < 0; }
  if op == _SEMVER_OP_LE { return cmp <= 0; }
  if op == _SEMVER_OP_CARET {
    if cmp < 0 { return false; }
    let ub = _caret_upper(&b, specified);
    return semver_compare(v, &ub) < 0;
  }
  if op == _SEMVER_OP_TILDE {
    if cmp < 0 { return false; }
    let ub = _tilde_upper(&b, specified);
    return semver_compare(v, &ub) < 0;
  }
  return false;
}

/// Test one single-comparator range against a version.
/// Params: v - the version; range - "*" or [= > >= < <= ^ ~] OPERAND.
/// Grammar: OPERAND is MAJOR[.MINOR[.PATCH]] with an optional -pre / +build
/// suffix and missing components zero-padded (">1.2" is ">1.2.0", "=1" is
/// "=1.0.0"). "^" upper bounds: ^1.2.3 <2.0.0, ^0.2.3 <0.3.0, ^0.0.3
/// <0.0.4, ^0.0 <0.1.0, ^0 <1.0.0. "~" upper bounds: ~1.2.3 and ~1.2 <1.3.0,
/// ~1 <2.0.0.
/// Returns: Ok(Bool) when the range is well formed; Err("semver: empty
/// range") for ""; Err("semver: malformed range: ...") for anything that is
/// not exactly one comparator (whitespace-AND lists like ">=1 <2"
/// included).
/// Error case: see above.
/// Complexity: O(len(range) + len(pre)).
pub fn semver_satisfies(v: &SemVer, range: Str) -> Result[Bool, Str] {
  let n = range.len();
  if n == 0 { return _bool_err("semver: empty range"); }
  if compare.str_compare(range, "*") == 0 { return _bool_ok(true); }

  var op = _SEMVER_OP_EXACT;
  var start = 0;
  let c0 = string.byte_at(range, 0);
  if c0 == _SEMVER_CARET {
    op = _SEMVER_OP_CARET;
    start = 1;
  } elif c0 == _SEMVER_TILDE {
    op = _SEMVER_OP_TILDE;
    start = 1;
  } elif c0 == _SEMVER_EQUALS {
    op = _SEMVER_OP_EXACT;
    start = 1;
  } elif c0 == _SEMVER_GREATER {
    op = _SEMVER_OP_GT;
    start = 1;
    if n >= 2 && string.byte_at(range, 1) == _SEMVER_EQUALS {
      op = _SEMVER_OP_GE;
      start = 2;
    }
  } elif c0 == _SEMVER_LESS {
    op = _SEMVER_OP_LT;
    start = 1;
    if n >= 2 && string.byte_at(range, 1) == _SEMVER_EQUALS {
      op = _SEMVER_OP_LE;
      start = 2;
    }
  }

  let operand = string.str_slice(range, start, n);
  let specified = _specified_components(operand);
  match _version_parse(operand, true) {
    Ok(b) => { return _bool_ok(_range_check(v, b, op, specified)); },
    Err(_) => { return _bool_err("semver: malformed range: " + range); },
  }
}

/// True when any range in `ranges` satisfies the version.
/// Params: v - the version; ranges - caller-built single-comparator ranges.
/// Returns: Ok(false) for an empty list; Ok(true) when any range matches;
/// Err from the first malformed range, even when an earlier range already
/// matched.
/// Error case: first malformed range error.
/// Complexity: O(sum of range lengths + len(pre)).
pub fn semver_satisfies_any(v: &SemVer, ranges: &Vec[Str]) -> Result[Bool, Str] {
  var any = false;
  var i = 0;
  while i < ranges.len() {
    let r: Str = ranges[i];
    let sr = semver_satisfies(v, r);
    match sr {
      Ok(b) => { if b { any = true; } },
      Err(e) => { return _bool_err(e); },
    }
    i = i + 1;
  }
  return _bool_ok(any);
}
