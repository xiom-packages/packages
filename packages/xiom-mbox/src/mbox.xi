// XIOM -- xiom.mbox: mbox mailbox codec: From-line message separation, mboxrd quoting, byte-range bodies, canonical emit
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a parsed mailbox is a flat Mailbox. `pool` is the whole input text,
// kept verbatim; every message is four index-aligned Vec[Int] byte ranges
// into it:
//   envelope line = pool[env_start[i], env_end[i])    ("From ..." without EOL)
//   message body  = pool[body_start[i], body_end[i]) (after the envelope
//                   line's terminator, up to the next delimiter)
// The final message's body runs to pool.len(), so an unterminated final
// message is accepted. Vec[StructType] is unsupported in this compiler, so
// the message list is deliberately four parallel Vec[Int] instead of a list
// of message structs.
//
// Separation rule (SPEC.md section 3):
//   * the pool must start with a "From " line, or be empty (Ok, zero
//     messages); anything else is Err;
//   * a later line starting with "From " opens a new message iff the physical
//     line immediately before it is empty; otherwise it is body content;
//   * a line terminator is LF or CRLF; a bare CR is an ordinary data byte;
//   * the empty line before a delimiter belongs to the preceding body span
//     (so a body parsed from canonical input ends with that blank line).
//
// mboxrd quoting stance, pinned (SPEC.md section 4):
//   * the pool keeps quoted lines verbatim and mbox_body_raw is verbatim;
//   * mbox_body_into materializes the decoded body: one ">" is removed from
//     every line matching ">+From " (mboxrd unquoting);
//   * mbox_emit re-quotes: a body line starting with "From " gains one ">",
//     so canonical input round-trips byte-for-byte and emit is idempotent.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the pool Str.
//   * Ok/Err for Result[Mailbox, Str] are constructed only in the tiny leaf
//     helpers _ok_mailbox/_err_mailbox (constructing Results directly inside
//     parse miscompiles in this compiler).
//   * Emitted bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str.
//   * Str equality (tests) goes through xiom.string.compare.str_compare
//     (BUG 17: `==` on Str values read from Vec[Str] elements lowers to a
//     pointer comparison).

module xiom.mbox

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(m) for Result[Mailbox, Str].
fn _ok_mailbox(m: Mailbox) -> Result[Mailbox, Str] {
  return Ok(m);
}

// Err(msg) for Result[Mailbox, Str].
fn _err_mailbox(msg: Str) -> Result[Mailbox, Str] {
  return Err(msg);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _MBOX_TAB: UInt8 = 9u8;
const _MBOX_LF: UInt8 = 10u8;
const _MBOX_CR: UInt8 = 13u8;
const _MBOX_SPACE: UInt8 = 32u8;
const _MBOX_GT: UInt8 = 62u8;
const _MBOX_F: UInt8 = 70u8;
const _MBOX_M: UInt8 = 109u8;
const _MBOX_O: UInt8 = 111u8;
const _MBOX_R: UInt8 = 114u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed mbox mailbox: `pool` is the whole input verbatim and each message
/// `i` occupies four index-aligned byte ranges into it (see the module
/// header). Accessors treat a hand-built Mailbox whose four vectors are not
/// aligned, or whose spans leave the pool, as invalid and return the empty
/// value documented per function.
pub type Mailbox = {
  pool: Str;
  env_start: Vec[Int];
  env_end: Vec[Int];
  body_start: Vec[Int];
  body_end: Vec[Int];
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte `i` of `s` widened to the 0..255 range.
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for an ASCII space or horizontal tab.
fn _is_ws(s: Str, i: Int) -> Bool {
  let b = string.byte_at(s, i);
  return b == _MBOX_SPACE || b == _MBOX_TAB;
}

// True when s[ls, le) begins with the five bytes "From " (a delimiter line
// prefix). A line shorter than five bytes, or the line "From", is not one.
fn _starts_with_from(s: Str, ls: Int, le: Int) -> Bool {
  if le - ls < 5 {
    return false;
  }
  if string.byte_at(s, ls) != _MBOX_F {
    return false;
  }
  if string.byte_at(s, ls + 1) != _MBOX_R {
    return false;
  }
  if string.byte_at(s, ls + 2) != _MBOX_O {
    return false;
  }
  if string.byte_at(s, ls + 3) != _MBOX_M {
    return false;
  }
  return string.byte_at(s, ls + 4) == _MBOX_SPACE;
}

// Index of the first LF in s[from, limit), or -1.
fn _find_lf(s: Str, from: Int, limit: Int) -> Int {
  var i = from;
  while i < limit {
    if string.byte_at(s, i) == _MBOX_LF {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// End of the line content for the physical line starting at `ls`: the LF is
// not part of the content, and the CR of a CRLF terminator is not either. A
// lone CR is data, not a terminator. Returns `limit` for an unterminated
// final line.
fn _line_end(s: Str, ls: Int, limit: Int) -> Int {
  let lf = _find_lf(s, ls, limit);
  if lf < 0 {
    return limit;
  }
  if lf > ls && string.byte_at(s, lf - 1) == _MBOX_CR {
    return lf - 1;
  }
  return lf;
}

// Start of the next physical line after the one at `ls` (after the LF, or
// after the CRLF pair); `limit` for an unterminated final line.
fn _line_next(s: Str, ls: Int, limit: Int) -> Int {
  let lf = _find_lf(s, ls, limit);
  if lf < 0 {
    return limit;
  }
  return lf + 1;
}

// Number of leading '>' bytes in s[ls, le).
fn _gt_count(s: Str, ls: Int, le: Int) -> Int {
  var k = 0;
  while ls + k < le && string.byte_at(s, ls + k) == _MBOX_GT {
    k = k + 1;
  }
  return k;
}

// Append s[from, to) to `out`; returns the number of bytes appended.
fn _push_span(out: &mut Vec[UInt8], s: Str, from: Int, to: Int) -> Int {
  var i = from;
  while i < to {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return to - from;
}

// Append one decoded body line s[ls, le) plus its terminator s[le, next) to
// `out`; returns the number of bytes appended. A line matching ">+From "
// loses exactly one '>' (mboxrd unquoting); the terminator bytes are copied
// verbatim.
fn _push_decoded_line(out: &mut Vec[UInt8], s: Str, ls: Int, le: Int, next: Int) -> Int {
  let k = _gt_count(s, ls, le);
  if k >= 1 && _starts_with_from(s, ls + k, le) {
    return _push_span(out, s, ls + 1, le) + _push_span(out, s, le, next);
  }
  return _push_span(out, s, ls, le) + _push_span(out, s, le, next);
}

// Smallest of the four index-aligned vector lengths (message count for a
// hand-built mailbox whose vectors are not aligned).
fn _msg_count(m: &Mailbox) -> Int {
  var c = m.env_start.len();
  if m.env_end.len() < c {
    c = m.env_end.len();
  }
  if m.body_start.len() < c {
    c = m.body_start.len();
  }
  if m.body_end.len() < c {
    c = m.body_end.len();
  }
  return c;
}

// True when message `i` is inside every vector and its spans are ordered,
// inside the pool, and start with "From ".
fn _span_ok(m: &Mailbox, i: Int) -> Bool {
  if i < 0 {
    return false;
  }
  if i >= m.env_start.len() || i >= m.env_end.len() {
    return false;
  }
  if i >= m.body_start.len() || i >= m.body_end.len() {
    return false;
  }
  let pool: Str = m.pool;
  let es: Int = m.env_start[i];
  let ee: Int = m.env_end[i];
  let bs: Int = m.body_start[i];
  let be: Int = m.body_end[i];
  let n = pool.len();
  if es < 0 || es + 5 > ee {
    return false;
  }
  if ee > bs || bs > be || be > n {
    return false;
  }
  return _starts_with_from(pool, es, ee);
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one in-memory mbox mailbox.
/// Params: text - the whole mailbox (LF or CRLF line endings).
/// Returns: Ok(Mailbox) for an empty pool (zero messages) or a pool that
/// starts with a "From " line; Err("mbox: ...") when non-empty leading text
/// precedes the first "From " line. A line starting with "From " opens a new
/// message only at offset 0 or after an empty line; elsewhere it is body
/// content. An unterminated final message is accepted (its body runs to the
/// end of the pool). A bare CR is data, not a line terminator.
/// Complexity: O(total input length).
pub fn mbox_parse(text: Str) -> Result[Mailbox, Str] {
  var m = Mailbox{
    pool: text;
    env_start: Vec[Int].new();
    env_end: Vec[Int].new();
    body_start: Vec[Int].new();
    body_end: Vec[Int].new();
  };
  let n = text.len();
  if n == 0 {
    return _ok_mailbox(m);
  }
  if !_starts_with_from(text, 0, n) {
    return _err_mailbox("mbox: leading text before first From line");
  }
  var prev_blank = false;
  var line_start = 0;
  while line_start < n {
    let le = _line_end(text, line_start, n);
    let next = _line_next(text, line_start, n);
    if _starts_with_from(text, line_start, le) && (line_start == 0 || prev_blank) {
      if m.env_start.len() > 0 {
        m.body_end.push(line_start);
      }
      m.env_start.push(line_start);
      m.env_end.push(le);
      m.body_start.push(next);
    }
    prev_blank = le == line_start;
    line_start = next;
  }
  // Close the final message: its body runs to the end of the pool.
  if m.env_start.len() > 0 {
    m.body_end.push(n);
  }
  return _ok_mailbox(m);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of messages. Zero for an empty mailbox; for a hand-built mailbox
/// whose four vectors are not aligned, the smallest vector length.
/// Error case: none.
/// Complexity: O(1).
pub fn mbox_count(m: &Mailbox) -> Int {
  return _msg_count(m);
}

/// The envelope line of message `i` without its terminator, verbatim, e.g.
/// "From alice@example.com Mon Jan  1 00:00:00 2024"; "" for an invalid
/// index.
/// Error case: none ("" for an invalid index or a misaligned mailbox).
/// Complexity: O(1) plus the copy of the slice.
pub fn mbox_envelope_line(m: &Mailbox, i: Int) -> Str {
  if !_span_ok(m, i) {
    return "";
  }
  let pool: Str = m.pool;
  let es: Int = m.env_start[i];
  let ee: Int = m.env_end[i];
  return string.str_slice(pool, es, ee);
}

/// The first whitespace-delimited token after "From " in message `i`'s
/// envelope line, kept as raw text; "" when there is no token or the index is
/// invalid. No address validation is performed.
/// Error case: none.
/// Complexity: O(envelope line length).
pub fn mbox_envelope_address(m: &Mailbox, i: Int) -> Str {
  if !_span_ok(m, i) {
    return "";
  }
  let pool: Str = m.pool;
  let cs: Int = m.env_start[i] + 5;
  let ce: Int = m.env_end[i];
  var s = cs;
  while s < ce && _is_ws(pool, s) {
    s = s + 1;
  }
  var e = s;
  while e < ce && !_is_ws(pool, e) {
    e = e + 1;
  }
  return string.str_slice(pool, s, e);
}

/// The raw text after the address token (and the whitespace run following it)
/// in message `i`'s envelope line, with trailing spaces/tabs removed; "" when
/// there is no date text or the index is invalid. Kept raw: no date parsing.
/// Error case: none.
/// Complexity: O(envelope line length).
pub fn mbox_envelope_date(m: &Mailbox, i: Int) -> Str {
  if !_span_ok(m, i) {
    return "";
  }
  let pool: Str = m.pool;
  let cs: Int = m.env_start[i] + 5;
  let ce: Int = m.env_end[i];
  var s = cs;
  while s < ce && _is_ws(pool, s) {
    s = s + 1;
  }
  while s < ce && !_is_ws(pool, s) {
    s = s + 1;
  }
  while s < ce && _is_ws(pool, s) {
    s = s + 1;
  }
  var e = ce;
  while e > s && _is_ws(pool, e - 1) {
    e = e - 1;
  }
  return string.str_slice(pool, s, e);
}

/// Pool offset of the first byte of message `i`'s body (the byte after the
/// envelope line's terminator); -1 for an invalid index.
/// Error case: none.
/// Complexity: O(1).
pub fn mbox_body_offset(m: &Mailbox, i: Int) -> Int {
  if !_span_ok(m, i) {
    return -1;
  }
  let bs: Int = m.body_start[i];
  return bs;
}

/// Byte length of message `i`'s body: from `mbox_body_offset` to the next
/// delimiter's "F", or to the end of the pool for the final message. The
/// blank line that separates a message from the next delimiter is part of the
/// preceding body. 0 for an invalid index.
/// Error case: none.
/// Complexity: O(1).
pub fn mbox_body_len(m: &Mailbox, i: Int) -> Int {
  if !_span_ok(m, i) {
    return 0;
  }
  let bs: Int = m.body_start[i];
  let be: Int = m.body_end[i];
  return be - bs;
}

/// Message `i`'s body exactly as it appears in the pool, quoted lines
/// included; "" for an invalid index.
/// Error case: none.
/// Complexity: O(1) plus the copy of the slice.
pub fn mbox_body_raw(m: &Mailbox, i: Int) -> Str {
  if !_span_ok(m, i) {
    return "";
  }
  let pool: Str = m.pool;
  let bs: Int = m.body_start[i];
  let be: Int = m.body_end[i];
  return string.str_slice(pool, bs, be);
}

/// Append message `i`'s decoded body (mboxrd unquoting, terminators verbatim)
/// to the caller's buffer `out`; returns the number of bytes appended (0 for
/// an invalid index). The buffer is appended to, not cleared: pre-existing
/// bytes are preserved.
/// Error case: none.
/// Complexity: O(body length).
pub fn mbox_body_into(m: &Mailbox, i: Int, out: &mut Vec[UInt8]) -> Int {
  if !_span_ok(m, i) {
    return 0;
  }
  let pool: Str = m.pool;
  let bs: Int = m.body_start[i];
  let be: Int = m.body_end[i];
  var appended = 0;
  var ls = bs;
  while ls < be {
    let le = _line_end(pool, ls, be);
    let next = _line_next(pool, ls, be);
    appended = appended + _push_decoded_line(out, pool, ls, le, next);
    ls = next;
  }
  return appended;
}

/// Pool offset of the empty line that separates message `i`'s header block
/// from its (RFC 5322) body: the first zero-length line in the message body
/// span, or -1 when the span has no empty line. For an empty separator line
/// the offset is the first byte of its terminator; CRLF counts as one empty
/// line, and a bare CR is never a terminator. Valid for any message,
/// headerless ones included (an immediately empty body yields the body
/// offset).
/// Error case: none (-1 for an invalid index).
/// Complexity: O(body length).
pub fn mbox_header_separator(m: &Mailbox, i: Int) -> Int {
  if !_span_ok(m, i) {
    return -1;
  }
  let pool: Str = m.pool;
  let bs: Int = m.body_start[i];
  let be: Int = m.body_end[i];
  var ls = bs;
  while ls < be {
    let le = _line_end(pool, ls, be);
    let next = _line_next(pool, ls, be);
    if le == ls {
      return ls;
    }
    ls = next;
  }
  return -1;
}

/// Pool offset of the first byte after the header separator line, i.e. of the
/// message's RFC 5322 body; -1 when there is no separator line
/// (`mbox_header_separator` is -1) or an invalid index. May equal the end of
/// the message body (separator is the last line: headers, no body).
/// Error case: none.
/// Complexity: O(body length).
pub fn mbox_header_body_start(m: &Mailbox, i: Int) -> Int {
  let sep = mbox_header_separator(m, i);
  if sep < 0 {
    return -1;
  }
  let pool: Str = m.pool;
  let be: Int = m.body_end[i];
  let lf = _find_lf(pool, sep, be);
  if lf < 0 {
    return -1;
  }
  return lf + 1;
}

// --------------------------------------------------
//  Emitter
// --------------------------------------------------

/// Canonical emitter: serialize the parsed mailbox.
/// Shape, exactly (SPEC.md section 7): for every message, the envelope line
/// verbatim, then `eol`, then the decoded body with every line terminator
/// rewritten as `eol` and every line starting with "From " re-quoted with one
/// ">"; between consecutive messages exactly one empty line (the parsed body
/// already ends with it, so canonical input round-trips byte-for-byte). The
/// final message's body is written as parsed, without adding a terminator.
/// Params: m - a mailbox (parsed, or a hand-built aligned one); eol - the
/// line terminator to write, "\n" or "\r\n" (any other text is written
/// literally after the envelope line and between lines).
/// Returns: the serialized mailbox.
/// Error case: none.
/// Complexity: O(total body length).
pub fn mbox_emit(m: &Mailbox, eol: Str) -> Str {
  var out = Vec[UInt8].new();
  let pool: Str = m.pool;
  let count = _msg_count(m);
  var i = 0;
  while i < count {
    let es: Int = m.env_start[i];
    let ee: Int = m.env_end[i];
    _push_span(&mut out, pool, es, ee);
    builder.sb_push_str(&mut out, eol);
    let bs: Int = m.body_start[i];
    let be: Int = m.body_end[i];
    var wrote = false;
    var last_term = false;
    var last_blank = false;
    var ls = bs;
    while ls < be {
      let le = _line_end(pool, ls, be);
      let next = _line_next(pool, ls, be);
      if _starts_with_from(pool, ls, le) {
        builder.sb_push_str(&mut out, ">");
      }
      _push_span(&mut out, pool, ls, le);
      last_blank = le == ls;
      last_term = next > le;
      if last_term {
        builder.sb_push_str(&mut out, eol);
      }
      wrote = true;
      ls = next;
    }
    if i < count - 1 {
      if !wrote {
        builder.sb_push_str(&mut out, eol);
      } else if !last_term {
        builder.sb_push_str(&mut out, eol);
        builder.sb_push_str(&mut out, eol);
      } else if !last_blank {
        builder.sb_push_str(&mut out, eol);
      }
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
