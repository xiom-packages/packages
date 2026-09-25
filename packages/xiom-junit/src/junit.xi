// XIOM -- xiom.junit: JUnit XML report codec for a documented subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Supported subset (see SPEC.md for the exact grammar and error catalog):
// an optional <testsuites> wrapper (tests/failures/errors/skipped/time) with
// <testsuite name tests failures errors skipped time> children, each holding
// <testcase name classname time> children and at most one of <failure>,
// <error> or <skipped> (message/type attributes). Attribute values may be
// single- or double-quoted and are entity-decoded (&amp; &lt; &gt; &quot;
// &apos;, &#NN; and &#xHH;); outcome text content is opaque and passed
// through verbatim. No DTD, no CDATA, no namespaces, no timestamps and no
// xUnit schema beyond this subset.
//
// v0.61.3 notes that shaped this module:
//   * the report is FLAT: suites and cases live in parallel Vec fields
//     (Vec[StructType] is unsupported in this compiler) and element nesting
//     is an explicit context stack, so no recursion is needed;
//   * Ok/Err for Result[JUnitDoc, Str] are constructed only in the leaf
//     helpers _ok_doc/_err_doc (constructing Results elsewhere miscompiles);
//   * all Str equality goes through xiom.string.compare.str_compare, and
//     neither .len() nor str_len is trusted on Str values read from Vec[Str]
//     elements (BUG 17): _count_value and _push_str_bytes scan bytes until
//     the NUL terminator instead;
//   * no FFI: text output is collected with xiom.string.builder over
//     Vec[UInt8] and materialized with sb_to_str (single allocation).

module xiom.junit

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Outcome codes
// --------------------------------------------------

/// Outcome code of a testcase with no outcome element (it passed).
pub const JUNIT_PASSED: Int = 0;
/// Outcome code of a testcase with a <failure> element.
pub const JUNIT_FAILURE: Int = 1;
/// Outcome code of a testcase with an <error> element.
pub const JUNIT_ERROR: Int = 2;
/// Outcome code of a testcase with a <skipped> element.
pub const JUNIT_SKIPPED: Int = 3;

// --------------------------------------------------
//  Report container
// --------------------------------------------------

/// Parsed JUnit report: a flat, parallel-vector model. All suites occupy
/// indices 0..junit_suite_count(d) of the six suite_* vectors in document
/// order; all cases occupy indices 0..junit_case_count(d) of the eight
/// case_* vectors in document order, and case_suites[i] is the owning suite
/// index. has_wrapper is 1 when the input had a <testsuites> root and 0 when
/// a bare <testsuite> was the root; total_* mirror the wrapper attributes
/// (0/"" when the wrapper or attribute is absent). case_outcomes[i] is one of
/// the JUNIT_* constants; case_messages/case_types/case_texts[i] describe the
/// case's single outcome element (message/type attributes decoded, text
/// opaque). Read fields through the accessors below so out-of-range indices
/// stay safe.
pub type JUnitDoc = {
  has_wrapper: Int;
  total_tests: Int;
  total_failures: Int;
  total_errors: Int;
  total_skipped: Int;
  total_time: Str;
  suite_names: Vec[Str];
  suite_tests: Vec[Int];
  suite_failures: Vec[Int];
  suite_errors: Vec[Int];
  suite_skipped: Vec[Int];
  suite_times: Vec[Str];
  case_suites: Vec[Int];
  case_names: Vec[Str];
  case_classnames: Vec[Str];
  case_times: Vec[Str];
  case_outcomes: Vec[Int];
  case_messages: Vec[Str];
  case_types: Vec[Str];
  case_texts: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[JUnitDoc, Str].
fn _ok_doc(d: JUnitDoc) -> Result[JUnitDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[JUnitDoc, Str].
fn _err_doc(m: Str) -> Result[JUnitDoc, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _J_LT: UInt8 = 60u8;
const _J_GT: UInt8 = 62u8;
const _J_SLASH: UInt8 = 47u8;
const _J_EQ: UInt8 = 61u8;
const _J_BANG: UInt8 = 33u8;
const _J_QUEST: UInt8 = 63u8;
const _J_DQUOTE: UInt8 = 34u8;
const _J_SQUOTE: UInt8 = 39u8;
const _J_HASH: UInt8 = 35u8;
const _J_AMP: UInt8 = 38u8;
const _J_SEMI: UInt8 = 59u8;
const _J_SPACE: UInt8 = 32u8;
const _J_TAB: UInt8 = 9u8;
const _J_CR: UInt8 = 13u8;
const _J_LF: UInt8 = 10u8;
const _J_DASH: UInt8 = 45u8;
const _J_LOWER_X: UInt8 = 120u8;
const _J_UPPER_X: UInt8 = 88u8;

// --------------------------------------------------
//  Parser state
// --------------------------------------------------

// Flat attribute list of one tag (parallel vectors; duplicates keep the first
// occurrence in _attr_value).
type _Attrs = {
  names: Vec[Str];
  values: Vec[Str];
}

// Mutable parse state. text/pos are the input cursor; suite_*/case_* mirror
// JUnitDoc while parsing; ctx_kind/ctx_idx/ctx_name are the open-element
// stack (kind 1 = testsuites, 2 = testsuite, 3 = testcase; an empty stack is
// the document level). root_seen tracks whether a top-level element was
// opened; failed/error carry the first failure.
type _JUnitParser = {
  text: Str;
  pos: Int;
  root_seen: Bool;
  has_wrapper: Int;
  total_tests: Int;
  total_failures: Int;
  total_errors: Int;
  total_skipped: Int;
  total_time: Str;
  suite_names: Vec[Str];
  suite_tests: Vec[Int];
  suite_failures: Vec[Int];
  suite_errors: Vec[Int];
  suite_skipped: Vec[Int];
  suite_times: Vec[Str];
  case_suites: Vec[Int];
  case_names: Vec[Str];
  case_classnames: Vec[Str];
  case_times: Vec[Str];
  case_outcomes: Vec[Int];
  case_messages: Vec[Str];
  case_types: Vec[Str];
  case_texts: Vec[Str];
  ctx_kind: Vec[Int];
  ctx_idx: Vec[Int];
  ctx_name: Vec[Str];
  failed: Bool;
  error: Str;
}

// Record the first failure and return false so callers can `return _fail(...)`.
fn _fail(p: &mut _JUnitParser, m: Str) -> Bool {
  p.failed = true;
  p.error = m;
  return false;
}

// --------------------------------------------------
//  Byte predicates and scanning helpers
// --------------------------------------------------

// ASCII whitespace byte: space, tab, LF or CR.
fn _is_ws(b: UInt8) -> Bool {
  if b == _J_SPACE {
    return true;
  }
  if b == _J_TAB {
    return true;
  }
  if b == _J_CR {
    return true;
  }
  if b == _J_LF {
    return true;
  }
  return false;
}

// ASCII digit byte: 0-9.
fn _is_digit_byte(b: UInt8) -> Bool {
  return b >= 48u8 && b <= 57u8;
}

// Byte that terminates a tag/attribute name: whitespace, '<', '>', '/' or '='.
fn _is_name_end(b: UInt8) -> Bool {
  if _is_ws(b) {
    return true;
  }
  if b == _J_LT {
    return true;
  }
  if b == _J_GT {
    return true;
  }
  if b == _J_SLASH {
    return true;
  }
  if b == _J_EQ {
    return true;
  }
  return false;
}

// Index of the first occurrence of `needle` at or after `from`, -1 when
// absent. Byte comparison only (no Str equality on inputs).
fn _find_seq(p: &mut _JUnitParser, needle: Str, from: Int) -> Int {
  let n = p.text.len();
  let m = needle.len();
  var i = from;
  while i + m <= n {
    var j = 0;
    var hit = true;
    while j < m {
      if string.byte_at(p.text, i + j) != string.byte_at(needle, j) {
        hit = false;
        break;
      }
      j = j + 1;
    }
    if hit {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// UTF-8-encode `code` (1..0x10FFFF) and append it to `out`.
fn _push_utf8(out: &mut Vec[UInt8], code: Int) {
  if code <= 127 {
    out.push(code as UInt8);
    return;
  }
  if code <= 2047 {
    out.push((192 + code / 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  if code <= 65535 {
    out.push((224 + code / 4096) as UInt8);
    out.push((128 + (code / 64) % 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  out.push((240 + code / 262144) as UInt8);
  out.push((128 + (code / 4096) % 64) as UInt8);
  out.push((128 + (code / 64) % 64) as UInt8);
  out.push((128 + code % 64) as UInt8);
}

// Codepoint of a "#NN" or "#xHH" numeric reference body, -1 when malformed,
// out of range (> U+10FFFF) or NUL. `body` is a fresh slice (safe .len()).
fn _entity_code(body: Str) -> Int {
  let n = body.len();
  if n < 2 {
    return -1;
  }
  if string.byte_at(body, 0) != _J_HASH {
    return -1;
  }
  var i = 1;
  var base = 10;
  let mark = string.byte_at(body, i);
  if mark == _J_LOWER_X || mark == _J_UPPER_X {
    base = 16;
    i = i + 1;
  }
  if i >= n {
    return -1;
  }
  var v = 0;
  while i < n {
    let b = (string.byte_at(body, i) as Int) & 0xFF;
    var d = -1;
    if b >= 48 && b <= 57 {
      d = b - 48;
    } elif base == 16 && b >= 97 && b <= 102 {
      d = b - 87;
    } elif base == 16 && b >= 65 && b <= 70 {
      d = b - 55;
    } else {
      return -1;
    }
    if d >= base {
      return -1;
    }
    v = v * base + d;
    if v > 1114111 {
      return -1;
    }
    i = i + 1;
  }
  if v == 0 {
    return -1;
  }
  return v;
}

// Decode one entity at raw[at] (which must be '&'); returns the number of
// input bytes consumed. In attribute values any unknown, malformed or
// unterminated reference is Err("junit: bad entity") (strict, unlike the
// pass-through outcome text).
fn _push_entity(p: &mut _JUnitParser, raw: Str, at: Int, end: Int, out: &mut Vec[UInt8]) -> Int {
  var semi = -1;
  var j = at + 1;
  while j < end {
    if string.byte_at(raw, j) == _J_SEMI {
      semi = j;
      break;
    }
    j = j + 1;
  }
  if semi < 0 {
    p.failed = true;
    p.error = "junit: bad entity";
    return end - at;
  }
  let body = string.str_slice(raw, at + 1, semi);
  if compare.str_compare(body, "amp") == 0 {
    out.push(_J_AMP);
    return semi - at + 1;
  }
  if compare.str_compare(body, "lt") == 0 {
    out.push(_J_LT);
    return semi - at + 1;
  }
  if compare.str_compare(body, "gt") == 0 {
    out.push(_J_GT);
    return semi - at + 1;
  }
  if compare.str_compare(body, "quot") == 0 {
    out.push(_J_DQUOTE);
    return semi - at + 1;
  }
  if compare.str_compare(body, "apos") == 0 {
    out.push(_J_SQUOTE);
    return semi - at + 1;
  }
  let code = _entity_code(body);
  if code > 0 {
    _push_utf8(out, code);
    return semi - at + 1;
  }
  p.failed = true;
  p.error = "junit: bad entity";
  return end - at;
}

// Entity-decode an attribute value slice into a fresh Str. On a bad entity the
// parser is marked failed and the (unused) partial value is returned.
fn _decode_value(p: &mut _JUnitParser, raw: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = raw.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(raw, i);
    if b == _J_AMP {
      let adv = _push_entity(p, raw, i, n, &mut out);
      i = i + adv;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Attribute parsing
// --------------------------------------------------

// Parse a decimal count attribute value: "" and all-digit values of at most
// 18 digits are accepted; anything else is Err("junit: invalid integer
// attribute"). The byte scan stops at the NUL terminator because .len() is
// not trusted on Vec[Str] element values (BUG 17).
fn _count_value(p: &mut _JUnitParser, s: Str) -> Int {
  if compare.str_compare(s, "") == 0 {
    return 0;
  }
  var v = 0;
  var i = 0;
  while i < 18 {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 0 {
      return v;
    }
    if b < 48 || b > 57 {
      p.failed = true;
      p.error = "junit: invalid integer attribute";
      return 0;
    }
    v = v * 10 + (b - 48);
    i = i + 1;
  }
  p.failed = true;
  p.error = "junit: invalid integer attribute";
  return 0;
}

// First attribute with `name` (byte comparison), None when absent; duplicate
// attribute names keep the first occurrence.
fn _attr_value(attrs: &_Attrs, name: Str) -> Option[Str] {
  var i = 0;
  while i < attrs.names.len() {
    let an: Str = attrs.names[i];
    if compare.str_compare(an, name) == 0 {
      return Some(attrs.values[i]);
    }
    i = i + 1;
  }
  return None;
}

// Value of attribute `name` as a decoded Str, "" when absent.
fn _attr_str(attrs: &_Attrs, name: Str) -> Str {
  let found = _attr_value(attrs, name);
  match found {
    Some(v) => { return v; },
    None => {},
  }
  return "";
}

// Value of count attribute `name` as an Int, 0 when absent; marks the parser
// failed on a non-decimal value.
fn _attr_count(p: &mut _JUnitParser, attrs: &_Attrs, name: Str) -> Int {
  let found = _attr_value(attrs, name);
  match found {
    Some(v) => { return _count_value(p, v); },
    None => {},
  }
  return 0;
}

// Parse the attributes of the current tag into `attrs`. Returns 0 for a ">"
// close, 1 for "/>", -1 on failure (parser marked). Unknown attribute names
// are collected too; the tag-specific readers ignore what they do not know.
fn _parse_attrs(p: &mut _JUnitParser, attrs: &mut _Attrs) -> Int {
  let n = p.text.len();
  loop {
    while p.pos < n && _is_ws(string.byte_at(p.text, p.pos)) {
      p.pos = p.pos + 1;
    }
    if p.pos >= n {
      return _parse_attrs_fail(p, "junit: premature EOF");
    }
    let b = string.byte_at(p.text, p.pos);
    if b == _J_GT {
      p.pos = p.pos + 1;
      return 0;
    }
    if b == _J_SLASH {
      p.pos = p.pos + 1;
      while p.pos < n && _is_ws(string.byte_at(p.text, p.pos)) {
        p.pos = p.pos + 1;
      }
      if p.pos >= n {
        return _parse_attrs_fail(p, "junit: premature EOF");
      }
      if string.byte_at(p.text, p.pos) != _J_GT {
        return _parse_attrs_fail(p, "junit: malformed tag");
      }
      p.pos = p.pos + 1;
      return 1;
    }
    let name_start = p.pos;
    while p.pos < n {
      if _is_name_end(string.byte_at(p.text, p.pos)) {
        break;
      }
      p.pos = p.pos + 1;
    }
    if p.pos == name_start {
      return _parse_attrs_fail(p, "junit: malformed attribute");
    }
    let aname = string.str_slice(p.text, name_start, p.pos);
    while p.pos < n && _is_ws(string.byte_at(p.text, p.pos)) {
      p.pos = p.pos + 1;
    }
    if p.pos >= n {
      return _parse_attrs_fail(p, "junit: premature EOF");
    }
    if string.byte_at(p.text, p.pos) != _J_EQ {
      return _parse_attrs_fail(p, "junit: malformed attribute");
    }
    p.pos = p.pos + 1;
    while p.pos < n && _is_ws(string.byte_at(p.text, p.pos)) {
      p.pos = p.pos + 1;
    }
    if p.pos >= n {
      return _parse_attrs_fail(p, "junit: premature EOF");
    }
    let q = string.byte_at(p.text, p.pos);
    if q != _J_DQUOTE && q != _J_SQUOTE {
      return _parse_attrs_fail(p, "junit: unquoted attribute");
    }
    p.pos = p.pos + 1;
    let v_start = p.pos;
    while p.pos < n {
      if string.byte_at(p.text, p.pos) == q {
        break;
      }
      p.pos = p.pos + 1;
    }
    if p.pos >= n {
      return _parse_attrs_fail(p, "junit: premature EOF");
    }
    let raw = string.str_slice(p.text, v_start, p.pos);
    p.pos = p.pos + 1;
    let val = _decode_value(p, raw);
    if p.failed {
      return -1;
    }
    var dup = false;
    var k = 0;
    while k < attrs.names.len() {
      let existing: Str = attrs.names[k];
      if compare.str_compare(existing, aname) == 0 {
        dup = true;
        break;
      }
      k = k + 1;
    }
    if !dup {
      attrs.names.push(aname);
      attrs.values.push(val);
    }
  }
  return 0;
}

// Fail `_parse_attrs` (which returns an Int, not a Bool) with message `m`.
fn _parse_attrs_fail(p: &mut _JUnitParser, m: Str) -> Int {
  p.failed = true;
  p.error = m;
  return -1;
}

// --------------------------------------------------
//  Context stack
// --------------------------------------------------

// Kind of the innermost open element: 0 = document, 1 = testsuites,
// 2 = testsuite, 3 = testcase.
fn _ctx_kind(p: &_JUnitParser) -> Int {
  if p.ctx_kind.len() == 0 {
    return 0;
  }
  let k: Int = p.ctx_kind[p.ctx_kind.len() - 1];
  return k;
}

// Index recorded for the innermost open element (suite or case index; -1 for
// the wrapper).
fn _ctx_index(p: &_JUnitParser) -> Int {
  if p.ctx_idx.len() == 0 {
    return -1;
  }
  let i: Int = p.ctx_idx[p.ctx_idx.len() - 1];
  return i;
}

fn _push_ctx(p: &mut _JUnitParser, kind: Int, idx: Int, name: Str) {
  p.ctx_kind.push(kind);
  p.ctx_idx.push(idx);
  p.ctx_name.push(name);
}

fn _pop_ctx(p: &mut _JUnitParser) {
  p.ctx_kind.pop();
  p.ctx_idx.pop();
  p.ctx_name.pop();
}

// --------------------------------------------------
//  Whitespace, comments and processing instructions
// --------------------------------------------------

// Skip whitespace, <!-- --> comments and <?...?> processing instructions.
// Comments and PIs are accepted wherever whitespace is accepted. Returns
// false (parser marked) only for an unterminated comment or PI.
fn _skip_misc(p: &mut _JUnitParser) -> Bool {
  let n = p.text.len();
  loop {
    while p.pos < n && _is_ws(string.byte_at(p.text, p.pos)) {
      p.pos = p.pos + 1;
    }
    if p.pos >= n {
      return true;
    }
    if string.byte_at(p.text, p.pos) != _J_LT {
      return true;
    }
    if p.pos + 1 >= n {
      return true;
    }
    let b2 = string.byte_at(p.text, p.pos + 1);
    if b2 == _J_QUEST {
      let close = _find_seq(p, "?>", p.pos + 1);
      if close < 0 {
        p.failed = true;
        p.error = "junit: premature EOF";
        return false;
      }
      p.pos = close + 2;
    } elif b2 == _J_BANG {
      if p.pos + 3 < n {
        if string.byte_at(p.text, p.pos + 2) == _J_DASH {
          if string.byte_at(p.text, p.pos + 3) == _J_DASH {
            let cclose = _find_seq(p, "-->", p.pos + 3);
            if cclose < 0 {
              p.failed = true;
              p.error = "junit: premature EOF";
              return false;
            }
            p.pos = cclose + 3;
          } else {
            return true;
          }
        } else {
          return true;
        }
      } else {
        return true;
      }
    } else {
      return true;
    }
  }
  return true;
}

// --------------------------------------------------
//  Markup consumption
// --------------------------------------------------

// Consume a close tag (p.pos at the first name byte after "</").
fn _close_tag(p: &mut _JUnitParser) -> Bool {
  let n = p.text.len();
  let start = p.pos;
  while p.pos < n {
    if _is_name_end(string.byte_at(p.text, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
  if p.pos == start {
    return _fail(p, "junit: mismatched closing tag");
  }
  let name = string.str_slice(p.text, start, p.pos);
  while p.pos < n && _is_ws(string.byte_at(p.text, p.pos)) {
    p.pos = p.pos + 1;
  }
  if p.pos >= n {
    return _fail(p, "junit: premature EOF");
  }
  if string.byte_at(p.text, p.pos) != _J_GT {
    return _fail(p, "junit: malformed tag");
  }
  p.pos = p.pos + 1;
  if _ctx_kind(p) == 0 {
    return _fail(p, "junit: mismatched closing tag");
  }
  let top: Str = p.ctx_name[p.ctx_name.len() - 1];
  if compare.str_compare(top, name) != 0 {
    return _fail(p, "junit: mismatched closing tag");
  }
  _pop_ctx(p);
  return true;
}

// Open the <testsuites> wrapper.
fn _open_testsuites(p: &mut _JUnitParser) -> Bool {
  if _ctx_kind(p) != 0 {
    return _fail(p, "junit: misplaced tag 'testsuites'");
  }
  if p.root_seen {
    return _fail(p, "junit: misplaced tag 'testsuites'");
  }
  var attrs = _Attrs{ names: Vec[Str].new(); values: Vec[Str].new(); };
  let sc = _parse_attrs(p, &mut attrs);
  if sc < 0 {
    return false;
  }
  p.root_seen = true;
  p.has_wrapper = 1;
  p.total_tests = _attr_count(p, &attrs, "tests");
  if p.failed {
    return false;
  }
  p.total_failures = _attr_count(p, &attrs, "failures");
  if p.failed {
    return false;
  }
  p.total_errors = _attr_count(p, &attrs, "errors");
  if p.failed {
    return false;
  }
  p.total_skipped = _attr_count(p, &attrs, "skipped");
  if p.failed {
    return false;
  }
  p.total_time = _attr_str(&attrs, "time");
  if sc == 0 {
    _push_ctx(p, 1, -1, "testsuites");
  }
  return true;
}

// Open a <testsuite> element (root or wrapper child).
fn _open_testsuite(p: &mut _JUnitParser) -> Bool {
  let kind = _ctx_kind(p);
  if kind != 0 && kind != 1 {
    return _fail(p, "junit: misplaced tag 'testsuite'");
  }
  if kind == 0 && p.root_seen {
    return _fail(p, "junit: misplaced tag 'testsuite'");
  }
  var attrs = _Attrs{ names: Vec[Str].new(); values: Vec[Str].new(); };
  let sc = _parse_attrs(p, &mut attrs);
  if sc < 0 {
    return false;
  }
  let nm = _attr_str(&attrs, "name");
  if compare.str_compare(nm, "") == 0 {
    return _fail(p, "junit: missing name");
  }
  let stests = _attr_count(p, &attrs, "tests");
  if p.failed {
    return false;
  }
  let sfail = _attr_count(p, &attrs, "failures");
  if p.failed {
    return false;
  }
  let serr = _attr_count(p, &attrs, "errors");
  if p.failed {
    return false;
  }
  let sskip = _attr_count(p, &attrs, "skipped");
  if p.failed {
    return false;
  }
  let stime = _attr_str(&attrs, "time");
  if kind == 0 {
    p.root_seen = true;
  }
  p.suite_names.push(nm);
  p.suite_tests.push(stests);
  p.suite_failures.push(sfail);
  p.suite_errors.push(serr);
  p.suite_skipped.push(sskip);
  p.suite_times.push(stime);
  let idx = p.suite_names.len() - 1;
  if sc == 0 {
    _push_ctx(p, 2, idx, "testsuite");
  }
  return true;
}

// Open a <testcase> element (testsuite child only).
fn _open_testcase(p: &mut _JUnitParser) -> Bool {
  let kind = _ctx_kind(p);
  if kind == 3 {
    return _fail(p, "junit: nested testcase");
  }
  if kind != 2 {
    return _fail(p, "junit: misplaced tag 'testcase'");
  }
  var attrs = _Attrs{ names: Vec[Str].new(); values: Vec[Str].new(); };
  let sc = _parse_attrs(p, &mut attrs);
  if sc < 0 {
    return false;
  }
  let nm = _attr_str(&attrs, "name");
  if compare.str_compare(nm, "") == 0 {
    return _fail(p, "junit: missing name");
  }
  let cn = _attr_str(&attrs, "classname");
  let tm = _attr_str(&attrs, "time");
  let owner = _ctx_index(p);
  p.case_suites.push(owner);
  p.case_names.push(nm);
  p.case_classnames.push(cn);
  p.case_times.push(tm);
  p.case_outcomes.push(0);
  p.case_messages.push("");
  p.case_types.push("");
  p.case_texts.push("");
  let idx = p.case_names.len() - 1;
  if sc == 0 {
    _push_ctx(p, 3, idx, "testcase");
  }
  return true;
}

// Open a <failure>, <error> or <skipped> element (at most one per testcase).
// When the element is not self-closing, its content is the raw text up to the
// first literal `</name>` (opaque pass-through; no nested markup is parsed).
fn _open_outcome(p: &mut _JUnitParser, name: Str, outcome: Int) -> Bool {
  let kind = _ctx_kind(p);
  if kind != 3 {
    return _fail(p, "junit: misplaced tag '" + name + "'");
  }
  let c = _ctx_index(p);
  let cur: Int = p.case_outcomes[c];
  if cur != 0 {
    return _fail(p, "junit: misplaced tag '" + name + "'");
  }
  var attrs = _Attrs{ names: Vec[Str].new(); values: Vec[Str].new(); };
  let sc = _parse_attrs(p, &mut attrs);
  if sc < 0 {
    return false;
  }
  p.case_outcomes[c] = outcome;
  p.case_messages[c] = _attr_str(&attrs, "message");
  p.case_types[c] = _attr_str(&attrs, "type");
  if sc == 0 {
    let closer = "</" + name + ">";
    let close = _find_seq(p, closer, p.pos);
    if close < 0 {
      return _fail(p, "junit: premature EOF");
    }
    p.case_texts[c] = string.str_slice(p.text, p.pos, close);
    p.pos = close + closer.len();
  }
  return true;
}

// Consume a start tag. p.pos is at the first byte after '<'.
fn _start_tag(p: &mut _JUnitParser) -> Bool {
  let n = p.text.len();
  let start = p.pos;
  while p.pos < n {
    if _is_name_end(string.byte_at(p.text, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
  let name = string.str_slice(p.text, start, p.pos);
  if compare.str_compare(name, "") == 0 {
    return _fail(p, "junit: unknown tag ''");
  }
  if compare.str_compare(name, "testsuites") == 0 {
    return _open_testsuites(p);
  }
  if compare.str_compare(name, "testsuite") == 0 {
    return _open_testsuite(p);
  }
  if compare.str_compare(name, "testcase") == 0 {
    return _open_testcase(p);
  }
  if compare.str_compare(name, "failure") == 0 {
    return _open_outcome(p, name, JUNIT_FAILURE);
  }
  if compare.str_compare(name, "error") == 0 {
    return _open_outcome(p, name, JUNIT_ERROR);
  }
  if compare.str_compare(name, "skipped") == 0 {
    return _open_outcome(p, name, JUNIT_SKIPPED);
  }
  return _fail(p, "junit: unknown tag '" + name + "'");
}

// Consume markup after '<': a close tag, unsupported <!...> markup, or a
// start tag (comments and PIs are consumed by _skip_misc before this runs).
fn _consume_markup(p: &mut _JUnitParser) -> Bool {
  let n = p.text.len();
  if p.pos >= n {
    return _fail(p, "junit: premature EOF");
  }
  let b = string.byte_at(p.text, p.pos);
  if b == _J_SLASH {
    p.pos = p.pos + 1;
    return _close_tag(p);
  }
  if b == _J_BANG {
    return _fail(p, "junit: unsupported markup");
  }
  return _start_tag(p);
}

// --------------------------------------------------
//  Public parsing API
// --------------------------------------------------

/// Parse a JUnit XML report in the supported subset.
/// Params: text - the whole report as one Str.
/// Returns: Ok(doc) with the flat model; documents may start with an optional
/// prolog of whitespace, comments and processing instructions, then a
/// <testsuites> wrapper or a bare <testsuite> root. Whitespace between
/// elements is ignored, non-whitespace character data where elements are
/// expected is an error, and comments/PIs are accepted wherever whitespace is
/// accepted.
/// Error case: Err("junit: ...") on the first malformed construct; see
/// SPEC.md for the full catalog (mismatched closing tag, unknown/misplaced
/// tag, nested testcase, missing name, unquoted/malformed attribute, bad
/// entity, invalid integer attribute, text where elements expected,
/// premature EOF, unsupported markup).
/// Complexity: O(n) over the report bytes (entity decoding is linear).
pub fn junit_parse(text: Str) -> Result[JUnitDoc, Str] {
  var p = _JUnitParser{
    text: text; pos: 0; root_seen: false; has_wrapper: 0;
    total_tests: 0; total_failures: 0; total_errors: 0; total_skipped: 0; total_time: "";
    suite_names: Vec[Str].new(); suite_tests: Vec[Int].new(); suite_failures: Vec[Int].new();
    suite_errors: Vec[Int].new(); suite_skipped: Vec[Int].new(); suite_times: Vec[Str].new();
    case_suites: Vec[Int].new(); case_names: Vec[Str].new(); case_classnames: Vec[Str].new();
    case_times: Vec[Str].new(); case_outcomes: Vec[Int].new(); case_messages: Vec[Str].new();
    case_types: Vec[Str].new(); case_texts: Vec[Str].new();
    ctx_kind: Vec[Int].new(); ctx_idx: Vec[Int].new(); ctx_name: Vec[Str].new();
    failed: false; error: "";
  };
  let n = text.len();
  if !_skip_misc(&mut p) {
    return _err_doc(p.error);
  }
  if p.pos >= n {
    return _err_doc("junit: premature EOF");
  }
  if string.byte_at(p.text, p.pos) != _J_LT {
    return _err_doc("junit: text where elements expected");
  }
  p.pos = p.pos + 1;
  if !_consume_markup(&mut p) {
    return _err_doc(p.error);
  }
  while p.pos < n && !p.failed {
    if !_skip_misc(&mut p) {
      break;
    }
    if p.pos >= n {
      break;
    }
    if string.byte_at(p.text, p.pos) != _J_LT {
      p.failed = true;
      p.error = "junit: text where elements expected";
      break;
    }
    p.pos = p.pos + 1;
    if !_consume_markup(&mut p) {
      break;
    }
  }
  if p.failed {
    return _err_doc(p.error);
  }
  if p.ctx_kind.len() > 0 {
    return _err_doc("junit: premature EOF");
  }
  return _ok_doc(JUnitDoc{
    has_wrapper: p.has_wrapper;
    total_tests: p.total_tests; total_failures: p.total_failures;
    total_errors: p.total_errors; total_skipped: p.total_skipped;
    total_time: p.total_time;
    suite_names: p.suite_names; suite_tests: p.suite_tests;
    suite_failures: p.suite_failures; suite_errors: p.suite_errors;
    suite_skipped: p.suite_skipped; suite_times: p.suite_times;
    case_suites: p.case_suites; case_names: p.case_names;
    case_classnames: p.case_classnames; case_times: p.case_times;
    case_outcomes: p.case_outcomes; case_messages: p.case_messages;
    case_types: p.case_types; case_texts: p.case_texts;
  });
}

// --------------------------------------------------
//  Emitter
// --------------------------------------------------

// Append every byte of `s` up to the NUL terminator. Used for Str values that
// may come from Vec[Str] elements, whose .len() is not trusted (BUG 17).
fn _push_str_bytes(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  loop {
    let b = string.byte_at(s, i);
    if b == 0u8 {
      break;
    }
    out.push(b);
    i = i + 1;
  }
}

// Append `s` with attribute-value escaping: & < > " ' as named entities.
fn _push_escaped_attr(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  loop {
    let b = string.byte_at(s, i);
    if b == 0u8 {
      break;
    }
    if b == _J_AMP {
      builder.sb_push_str(out, "&amp;");
    } elif b == _J_LT {
      builder.sb_push_str(out, "&lt;");
    } elif b == _J_GT {
      builder.sb_push_str(out, "&gt;");
    } elif b == _J_DQUOTE {
      builder.sb_push_str(out, "&quot;");
    } elif b == _J_SQUOTE {
      builder.sb_push_str(out, "&apos;");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
}

// Append `name="value"` with the value escaped.
fn _push_attr(out: &mut Vec[UInt8], name: Str, value: Str) {
  out.push(_J_SPACE);
  builder.sb_push_str(out, name);
  builder.sb_push_str(out, "=\"");
  _push_escaped_attr(out, value);
  builder.sb_push_str(out, "\"");
}

// Append `name="value"` only when `value` is non-empty.
fn _push_opt_attr(out: &mut Vec[UInt8], name: Str, value: Str) {
  if compare.str_compare(value, "") == 0 {
    return;
  }
  _push_attr(out, name, value);
}

// Append `name="<v>"` (decimal).
fn _push_int_attr(out: &mut Vec[UInt8], name: Str, v: Int) {
  out.push(_J_SPACE);
  builder.sb_push_str(out, name);
  builder.sb_push_str(out, "=\"");
  builder.sb_push_int(out, v);
  builder.sb_push_str(out, "\"");
}

// Append two spaces per `level`.
fn _push_indent(out: &mut Vec[UInt8], level: Int) {
  var i = 0;
  while i < level * 2 {
    out.push(_J_SPACE);
    i = i + 1;
  }
}

// Tag name of an outcome code; any unrecognized non-zero code emits "failure".
fn _outcome_tag(outcome: Int) -> Str {
  if outcome == JUNIT_ERROR {
    return "error";
  }
  if outcome == JUNIT_SKIPPED {
    return "skipped";
  }
  return "failure";
}

// Emit one testcase line (level = indentation level).
fn _emit_case(out: &mut Vec[UInt8], d: &JUnitDoc, c: Int, level: Int) {
  _push_indent(out, level);
  builder.sb_push_str(out, "<testcase");
  let nm: Str = d.case_names[c];
  _push_attr(out, "name", nm);
  let cn: Str = d.case_classnames[c];
  _push_opt_attr(out, "classname", cn);
  let tm: Str = d.case_times[c];
  _push_opt_attr(out, "time", tm);
  let oc: Int = d.case_outcomes[c];
  if oc == 0 {
    builder.sb_push_str(out, "/>");
    out.push(_J_LF);
    return;
  }
  builder.sb_push_str(out, ">");
  out.push(_J_LF);
  _push_indent(out, level + 1);
  let tag = _outcome_tag(oc);
  builder.sb_push_str(out, "<");
  builder.sb_push_str(out, tag);
  let msg: Str = d.case_messages[c];
  _push_opt_attr(out, "message", msg);
  let ty: Str = d.case_types[c];
  _push_opt_attr(out, "type", ty);
  let txt: Str = d.case_texts[c];
  if compare.str_compare(txt, "") == 0 {
    builder.sb_push_str(out, "/>");
    out.push(_J_LF);
  } else {
    builder.sb_push_str(out, ">");
    _push_str_bytes(out, txt);
    builder.sb_push_str(out, "</");
    builder.sb_push_str(out, tag);
    builder.sb_push_str(out, ">");
    out.push(_J_LF);
  }
  _push_indent(out, level);
  builder.sb_push_str(out, "</testcase>");
  out.push(_J_LF);
}

// Emit one testsuite and its testcases (level = indentation level).
fn _emit_suite(out: &mut Vec[UInt8], d: &JUnitDoc, s: Int, level: Int) {
  _push_indent(out, level);
  builder.sb_push_str(out, "<testsuite");
  let nm: Str = d.suite_names[s];
  _push_attr(out, "name", nm);
  let st: Int = d.suite_tests[s];
  _push_int_attr(out, "tests", st);
  let sf: Int = d.suite_failures[s];
  _push_int_attr(out, "failures", sf);
  let se: Int = d.suite_errors[s];
  _push_int_attr(out, "errors", se);
  let sk: Int = d.suite_skipped[s];
  _push_int_attr(out, "skipped", sk);
  let tm: Str = d.suite_times[s];
  _push_opt_attr(out, "time", tm);
  builder.sb_push_str(out, ">");
  out.push(_J_LF);
  var c = 0;
  while c < junit_case_count(d) {
    let owner: Int = d.case_suites[c];
    if owner == s {
      _emit_case(out, d, c, level + 1);
    }
    c = c + 1;
  }
  _push_indent(out, level);
  builder.sb_push_str(out, "</testsuite>");
  out.push(_J_LF);
}

/// Serialize a parsed report back to canonical JUnit XML.
/// Params: d - the report to emit.
/// Returns: a deterministic Str. Canonical form: two-space indentation, one
/// element per line, attribute order tests, failures, errors, skipped, time
/// (suite/suite level) and name, classname, time (testcase), then message,
/// type (outcome). Count attributes are always emitted (0 when absent), the
/// optional time/classname attributes only when non-empty, and empty outcome
/// text collapses to a self-closing tag. Attribute values are escaped; outcome
/// text is opaque and emitted verbatim (matching the parser's pass-through
/// model). For any doc produced by junit_parse, re-parsing the output yields
/// an equal model (the emitted report is byte-stable across repeated runs).
/// Error case: none.
/// Complexity: O(suites + cases + output bytes).
pub fn junit_emit(d: &JUnitDoc) -> Str {
  var out = Vec[UInt8].new();
  var s = 0;
  if d.has_wrapper == 1 {
    builder.sb_push_str(&mut out, "<testsuites");
    _push_int_attr(&mut out, "tests", d.total_tests);
    _push_int_attr(&mut out, "failures", d.total_failures);
    _push_int_attr(&mut out, "errors", d.total_errors);
    _push_int_attr(&mut out, "skipped", d.total_skipped);
    _push_opt_attr(&mut out, "time", d.total_time);
    builder.sb_push_str(&mut out, ">");
    out.push(_J_LF);
    while s < junit_suite_count(d) {
      _emit_suite(&mut out, d, s, 1);
      s = s + 1;
    }
    builder.sb_push_str(&mut out, "</testsuites>");
    out.push(_J_LF);
  } else {
    while s < junit_suite_count(d) {
      _emit_suite(&mut out, d, s, 0);
      s = s + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Document accessors
// --------------------------------------------------

/// Whether the input had a <testsuites> wrapper root.
/// Params: d - the report.
/// Returns: true for a wrapper root, false for a bare <testsuite> root.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_has_wrapper(d: &JUnitDoc) -> Bool {
  return d.has_wrapper == 1;
}

/// Number of suites; the minimum length of all six suite vectors, so a
/// hand-built report with drifted vectors stays safe to traverse.
/// Params: d - the report.
/// Returns: the suite count; 0 for an empty report.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_suite_count(d: &JUnitDoc) -> Int {
  var n = d.suite_names.len();
  if d.suite_tests.len() < n { n = d.suite_tests.len(); }
  if d.suite_failures.len() < n { n = d.suite_failures.len(); }
  if d.suite_errors.len() < n { n = d.suite_errors.len(); }
  if d.suite_skipped.len() < n { n = d.suite_skipped.len(); }
  if d.suite_times.len() < n { n = d.suite_times.len(); }
  return n;
}

/// Number of testcases; the minimum length of all eight case vectors.
/// Params: d - the report.
/// Returns: the case count; 0 for an empty report.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_case_count(d: &JUnitDoc) -> Int {
  var n = d.case_names.len();
  if d.case_suites.len() < n { n = d.case_suites.len(); }
  if d.case_classnames.len() < n { n = d.case_classnames.len(); }
  if d.case_times.len() < n { n = d.case_times.len(); }
  if d.case_outcomes.len() < n { n = d.case_outcomes.len(); }
  if d.case_messages.len() < n { n = d.case_messages.len(); }
  if d.case_types.len() < n { n = d.case_types.len(); }
  if d.case_texts.len() < n { n = d.case_texts.len(); }
  return n;
}

/// Number of testcases with outcome `outcome`.
/// Params: d - the report; outcome - a JUNIT_* code (any other value counts 0).
/// Returns: the count.
/// Error case: none.
/// Complexity: O(cases).
pub fn junit_case_count_by_outcome(d: &JUnitDoc, outcome: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < d.case_outcomes.len() {
    let o: Int = d.case_outcomes[i];
    if o == outcome {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Name of suite `s`.
/// Params: d - the report; s - the suite index.
/// Returns: the name, or "" when `s` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_suite_name(d: &JUnitDoc, s: Int) -> Str {
  if s < 0 || s >= d.suite_names.len() {
    return "";
  }
  return d.suite_names[s];
}

/// Declared tests count of suite `s`.
/// Params: d - the report; s - the suite index.
/// Returns: the attribute value (0 when absent), or -1 when `s` is out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_suite_tests(d: &JUnitDoc, s: Int) -> Int {
  if s < 0 || s >= d.suite_tests.len() {
    return -1;
  }
  let v: Int = d.suite_tests[s];
  return v;
}

/// Declared failures count of suite `s`.
/// Params: d - the report; s - the suite index.
/// Returns: the attribute value (0 when absent), or -1 when `s` is out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_suite_failures(d: &JUnitDoc, s: Int) -> Int {
  if s < 0 || s >= d.suite_failures.len() {
    return -1;
  }
  let v: Int = d.suite_failures[s];
  return v;
}

/// Declared errors count of suite `s`.
/// Params: d - the report; s - the suite index.
/// Returns: the attribute value (0 when absent), or -1 when `s` is out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_suite_errors(d: &JUnitDoc, s: Int) -> Int {
  if s < 0 || s >= d.suite_errors.len() {
    return -1;
  }
  let v: Int = d.suite_errors[s];
  return v;
}

/// Declared skipped count of suite `s`.
/// Params: d - the report; s - the suite index.
/// Returns: the attribute value (0 when absent), or -1 when `s` is out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_suite_skipped(d: &JUnitDoc, s: Int) -> Int {
  if s < 0 || s >= d.suite_skipped.len() {
    return -1;
  }
  let v: Int = d.suite_skipped[s];
  return v;
}

/// Raw time text of suite `s` (never parsed as a number).
/// Params: d - the report; s - the suite index.
/// Returns: the attribute text as written ("" when absent or out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn junit_suite_time(d: &JUnitDoc, s: Int) -> Str {
  if s < 0 || s >= d.suite_times.len() {
    return "";
  }
  return d.suite_times[s];
}

/// Number of testcases owned by suite `s`.
/// Params: d - the report; s - the suite index.
/// Returns: the case count; 0 for an out-of-range suite index.
/// Error case: none.
/// Complexity: O(cases).
pub fn junit_suite_case_count(d: &JUnitDoc, s: Int) -> Int {
  if s < 0 || s >= junit_suite_count(d) {
    return 0;
  }
  var n = 0;
  var i = 0;
  while i < d.case_suites.len() {
    let owner: Int = d.case_suites[i];
    if owner == s {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Owning suite index of testcase `i`.
/// Params: d - the report; i - the case index.
/// Returns: the suite index, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_case_suite(d: &JUnitDoc, i: Int) -> Int {
  if i < 0 || i >= d.case_suites.len() {
    return -1;
  }
  let v: Int = d.case_suites[i];
  return v;
}

/// Name of testcase `i`.
/// Params: d - the report; i - the case index.
/// Returns: the name, or "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_case_name(d: &JUnitDoc, i: Int) -> Str {
  if i < 0 || i >= d.case_names.len() {
    return "";
  }
  return d.case_names[i];
}

/// Classname of testcase `i`.
/// Params: d - the report; i - the case index.
/// Returns: the classname ("" when the attribute was absent), or "" when `i`
/// is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_case_classname(d: &JUnitDoc, i: Int) -> Str {
  if i < 0 || i >= d.case_classnames.len() {
    return "";
  }
  return d.case_classnames[i];
}

/// Raw time text of testcase `i` (never parsed as a number).
/// Params: d - the report; i - the case index.
/// Returns: the attribute text as written ("" when absent or out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn junit_case_time(d: &JUnitDoc, i: Int) -> Str {
  if i < 0 || i >= d.case_times.len() {
    return "";
  }
  return d.case_times[i];
}

/// Outcome of testcase `i`: JUNIT_PASSED / JUNIT_FAILURE / JUNIT_ERROR /
/// JUNIT_SKIPPED.
/// Params: d - the report; i - the case index.
/// Returns: the outcome code, or -1 when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_case_outcome(d: &JUnitDoc, i: Int) -> Int {
  if i < 0 || i >= d.case_outcomes.len() {
    return -1;
  }
  let v: Int = d.case_outcomes[i];
  return v;
}

/// Message attribute of testcase `i`'s outcome element (decoded entities).
/// Params: d - the report; i - the case index.
/// Returns: the message ("" when there is no outcome or no message attribute,
/// or when `i` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn junit_case_message(d: &JUnitDoc, i: Int) -> Str {
  if i < 0 || i >= d.case_messages.len() {
    return "";
  }
  return d.case_messages[i];
}

/// Type attribute of testcase `i`'s outcome element (decoded entities).
/// Params: d - the report; i - the case index.
/// Returns: the type ("" when there is no outcome or no type attribute, or
/// when `i` is out of range).
/// Error case: none.
/// Complexity: O(1).
pub fn junit_case_type(d: &JUnitDoc, i: Int) -> Str {
  if i < 0 || i >= d.case_types.len() {
    return "";
  }
  return d.case_types[i];
}

/// Verbatim text content of testcase `i`'s outcome element.
/// Params: d - the report; i - the case index.
/// Returns: the raw text between the outcome start and end tags with no
/// entity decoding ("" when the outcome is self-closing/empty or `i` is out
/// of range).
/// Error case: none.
/// Complexity: O(1).
pub fn junit_case_text(d: &JUnitDoc, i: Int) -> Str {
  if i < 0 || i >= d.case_texts.len() {
    return "";
  }
  return d.case_texts[i];
}

/// Declared tests total of the <testsuites> wrapper.
/// Params: d - the report.
/// Returns: the attribute value, 0 when the wrapper or attribute is absent.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_total_tests(d: &JUnitDoc) -> Int {
  return d.total_tests;
}

/// Declared failures total of the <testsuites> wrapper (0 when absent).
/// Params: d - the report.
/// Returns: the attribute value.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_total_failures(d: &JUnitDoc) -> Int {
  return d.total_failures;
}

/// Declared errors total of the <testsuites> wrapper (0 when absent).
/// Params: d - the report.
/// Returns: the attribute value.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_total_errors(d: &JUnitDoc) -> Int {
  return d.total_errors;
}

/// Declared skipped total of the <testsuites> wrapper (0 when absent).
/// Params: d - the report.
/// Returns: the attribute value.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_total_skipped(d: &JUnitDoc) -> Int {
  return d.total_skipped;
}

/// Raw time text of the <testsuites> wrapper ("" when absent).
/// Params: d - the report.
/// Returns: the attribute text as written.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_total_time(d: &JUnitDoc) -> Str {
  return d.total_time;
}

/// Human-readable name of an outcome code: "passed", "failure", "error" or
/// "skipped".
/// Params: outcome - a JUNIT_* code.
/// Returns: the name, or "" for any other value.
/// Error case: none.
/// Complexity: O(1).
pub fn junit_outcome_name(outcome: Int) -> Str {
  if outcome == JUNIT_PASSED {
    return "passed";
  }
  if outcome == JUNIT_FAILURE {
    return "failure";
  }
  if outcome == JUNIT_ERROR {
    return "error";
  }
  if outcome == JUNIT_SKIPPED {
    return "skipped";
  }
  return "";
}
