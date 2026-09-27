// XIOM -- xiom.nats: NATS 1.x text protocol codec (client and server ops)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no session state) encoder/parser for the
// NATS 1.x text protocol as spoken by clients and servers on the wire:
//
//   client -> server: CONNECT, PUB, HPUB, SUB, UNSUB, PING, PONG
//   server -> client: INFO, MSG, HMSG, +OK, -ERR, PING, PONG
//
// Every op is CRLF-framed. PUB/HPUB/MSG/HMSG carry a decimal byte count in
// the control line and the payload is copied out verbatim by that count, so
// payloads may contain embedded NULs, CR, LF and any byte >= 128 (payloads
// stay Vec[UInt8] end to end -- they are never turned into a Str). HPUB and
// HMSG carry a NATS/1.0 header block followed by the payload; the declared
// total size covers both.
//
// Subjects are validated structurally at the byte level: tokens separated by
// '.', no empty tokens, '*' matches one token and '>' matches one or more and
// must be the final token. PUB/MSG subjects must be literal (no wildcards);
// SUB filters may use them. nats_subject_matches implements the wildcard
// match so callers can test a filter against a literal subject.
//
// Parsing is strictly one op at a time: nats_parse_op(data, off) returns the
// op together with `consumed`, the number of bytes to advance. Parse errors
// carry the op start offset in the message: "nats: <what> at <offset>".
//
// Small JSON key lookups (nats_json_str/int/bool/has) find the first scalar
// value whose key is a top-level member of the object text; they are lookup
// helpers, not a JSON parser (no escapes decoding, no nested objects, no
// arrays -- a wildcard-free INFO/CONNECT subset).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside other functions miscompiles);
//   * every byte read from a Vec[UInt8] widens with `(data[pos] as Int) &
//     0xFF` before it enters Int arithmetic or comparisons;
//   * Vec reads are bound to typed locals and struct fields are copied into
//     typed locals before they are passed by reference;
//   * free functions only, no match-in-src, no Vec[StructType], no
//     angle-bracket generics, no `log`, no floats.

module xiom.nats

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Byte constants (Int, always compared masked)
// --------------------------------------------------

const _NATS_TAB: Int = 9;
const _NATS_LF: Int = 10;
const _NATS_CR: Int = 13;
const _NATS_SPACE: Int = 32;
const _NATS_QUOTE: Int = 34;
const _NATS_STAR: Int = 42;
const _NATS_COMMA: Int = 44;
const _NATS_DASH: Int = 45;
const _NATS_DOT: Int = 46;
const _NATS_COLON: Int = 58;
const _NATS_GT: Int = 62;
const _NATS_LBRACKET: Int = 91;
const _NATS_BACKSLASH: Int = 92;
const _NATS_LBRACE: Int = 123;
const _NATS_RBRACE: Int = 125;
const _NATS_DEL: Int = 127;

// Control lines are at most 4096 bytes including the terminating CRLF
// (NATS default max_control_line).
const _NATS_MAX_CONTROL: Int = 4096;

// Largest accepted byte count / stream id: 2147483647 (2^31 - 1).
const _NATS_MAX_SIZE: Int = 2147483647;

// --------------------------------------------------
//  Op kinds
// --------------------------------------------------

const _NATS_K_CONNECT: Int = 1;
const _NATS_K_PUB: Int = 2;
const _NATS_K_HPUB: Int = 3;
const _NATS_K_SUB: Int = 4;
const _NATS_K_UNSUB: Int = 5;
const _NATS_K_PING: Int = 6;
const _NATS_K_PONG: Int = 7;
const _NATS_K_INFO: Int = 8;
const _NATS_K_MSG: Int = 9;
const _NATS_K_HMSG: Int = 10;
const _NATS_K_OK: Int = 11;
const _NATS_K_ERR: Int = 12;

/// Kind id of the CONNECT client op. Params: none. Returns: 1.
pub fn nats_kind_connect() -> Int { return _NATS_K_CONNECT; }

/// Kind id of the PUB client op. Params: none. Returns: 2.
pub fn nats_kind_pub() -> Int { return _NATS_K_PUB; }

/// Kind id of the HPUB client op. Params: none. Returns: 3.
pub fn nats_kind_hpub() -> Int { return _NATS_K_HPUB; }

/// Kind id of the SUB client op. Params: none. Returns: 4.
pub fn nats_kind_sub() -> Int { return _NATS_K_SUB; }

/// Kind id of the UNSUB client op. Params: none. Returns: 5.
pub fn nats_kind_unsub() -> Int { return _NATS_K_UNSUB; }

/// Kind id of the PING op (both directions). Params: none. Returns: 6.
pub fn nats_kind_ping() -> Int { return _NATS_K_PING; }

/// Kind id of the PONG op (both directions). Params: none. Returns: 7.
pub fn nats_kind_pong() -> Int { return _NATS_K_PONG; }

/// Kind id of the INFO server op. Params: none. Returns: 8.
pub fn nats_kind_info() -> Int { return _NATS_K_INFO; }

/// Kind id of the MSG server op. Params: none. Returns: 9.
pub fn nats_kind_msg() -> Int { return _NATS_K_MSG; }

/// Kind id of the HMSG server op. Params: none. Returns: 10.
pub fn nats_kind_hmsg() -> Int { return _NATS_K_HMSG; }

/// Kind id of the +OK server op. Params: none. Returns: 11.
pub fn nats_kind_ok() -> Int { return _NATS_K_OK; }

/// Kind id of the -ERR server op. Params: none. Returns: 12.
pub fn nats_kind_err() -> Int { return _NATS_K_ERR; }

/// Protocol op name of a kind id ("CONNECT" .. "-ERR"), "UNKNOWN" otherwise.
/// Params: kind - a kind id from nats_kind_*.
/// Returns: the uppercase wire name of the op.
/// Error case: none.
pub fn nats_kind_name(kind: Int) -> Str {
  if kind == _NATS_K_CONNECT { return "CONNECT"; }
  if kind == _NATS_K_PUB { return "PUB"; }
  if kind == _NATS_K_HPUB { return "HPUB"; }
  if kind == _NATS_K_SUB { return "SUB"; }
  if kind == _NATS_K_UNSUB { return "UNSUB"; }
  if kind == _NATS_K_PING { return "PING"; }
  if kind == _NATS_K_PONG { return "PONG"; }
  if kind == _NATS_K_INFO { return "INFO"; }
  if kind == _NATS_K_MSG { return "MSG"; }
  if kind == _NATS_K_HMSG { return "HMSG"; }
  if kind == _NATS_K_OK { return "+OK"; }
  if kind == _NATS_K_ERR { return "-ERR"; }
  return "UNKNOWN";
}

/// True when `kind` is an op a client sends (CONNECT, PUB, HPUB, SUB, UNSUB,
/// PING, PONG). Params: kind - a kind id. Returns: the predicate.
/// Error case: none.
pub fn nats_is_client_kind(kind: Int) -> Bool {
  if kind == _NATS_K_CONNECT { return true; }
  if kind == _NATS_K_PUB { return true; }
  if kind == _NATS_K_HPUB { return true; }
  if kind == _NATS_K_SUB { return true; }
  if kind == _NATS_K_UNSUB { return true; }
  if kind == _NATS_K_PING { return true; }
  if kind == _NATS_K_PONG { return true; }
  return false;
}

/// True when `kind` is an op a server sends (INFO, MSG, HMSG, +OK, -ERR and
/// the shared PING/PONG keepalive pair). Params: kind - a kind id.
/// Returns: the predicate. Error case: none.
pub fn nats_is_server_kind(kind: Int) -> Bool {
  if kind == _NATS_K_INFO { return true; }
  if kind == _NATS_K_MSG { return true; }
  if kind == _NATS_K_HMSG { return true; }
  if kind == _NATS_K_OK { return true; }
  if kind == _NATS_K_ERR { return true; }
  if kind == _NATS_K_PING { return true; }
  if kind == _NATS_K_PONG { return true; }
  return false;
}

/// Maximum control-line length in bytes including the terminating CRLF
/// (NATS default max_control_line). Params: none. Returns: 4096.
pub fn nats_max_control_line() -> Int { return _NATS_MAX_CONTROL; }

/// Maximum accepted byte count / stream id. Params: none.
/// Returns: 2147483647. Error case: none.
pub fn nats_max_payload_size() -> Int { return _NATS_MAX_SIZE; }

// --------------------------------------------------
//  Decoded op
// --------------------------------------------------

/// One decoded protocol op. `kind` is a nats_kind_* id. `subject` is the
/// subject or filter; `reply` the optional reply-to (empty when absent);
/// `queue` the optional SUB queue group (empty when absent); `sid` a SUB/
/// UNSUB/ MSG/HMSG stream id (0 when not applicable); `max_msgs` the UNSUB
/// auto-unsubscribe count (0 when absent); `header_size` and `total_size` the
/// declared HPUB/HMSG counts (0 for other ops); `payload` the raw bytes;
/// `headers` the NATS/1.0 block (empty unless HPUB/HMSG); `text` the CONNECT/
/// INFO JSON object or the -ERR message text (empty otherwise); `consumed`
/// the number of bytes the op occupied starting at the parse offset.
pub type NatsOp = {
  kind: Int;
  subject: Vec[UInt8];
  reply: Vec[UInt8];
  queue: Vec[UInt8];
  sid: Int;
  max_msgs: Int;
  header_size: Int;
  total_size: Int;
  payload: Vec[UInt8];
  headers: Vec[UInt8];
  text: Vec[UInt8];
  consumed: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[NatsOp, Str].
fn _ok_op(v: NatsOp) -> Result[NatsOp, Str] {
  return Ok(v);
}

// Err(m) for Result[NatsOp, Str].
fn _err_op(m: Str) -> Result[NatsOp, Str] {
  return Err(m);
}

// Ok(v) for Result[(Int, Int), Str].
fn _ok_pair(v: (Int, Int)) -> Result[(Int, Int), Str] {
  return Ok(v);
}

// Err(m) for Result[(Int, Int), Str].
fn _err_pair(m: Str) -> Result[(Int, Int), Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Decimal text of v for error messages (digits/sign only; never 0x00).
fn _int_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_int(&mut out, v);
  return builder.sb_to_str(&out);
}

// "<msg> at <off>": the error text convention of this module.
fn _at(msg: Str, off: Int) -> Str {
  return msg + " at " + _int_str(off);
}

// Append every byte of v to out.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append data[a, b) to out; callers guarantee the bounds.
fn _copy_span(data: &Vec[UInt8], a: Int, b: Int, out: &mut Vec[UInt8]) {
  var i = a;
  while i < b {
    out.push(data[i]);
    i = i + 1;
  }
}

// Append one ASCII space.
fn _push_space(out: &mut Vec[UInt8]) {
  out.push(32 as UInt8);
}

// Append CR LF.
fn _push_crlf(out: &mut Vec[UInt8]) {
  out.push(13 as UInt8);
  out.push(10 as UInt8);
}

// --------------------------------------------------
//  Span predicates
// --------------------------------------------------

// Index of the CR of the first CRLF in [from, limit), or -1.
fn _find_crlf(data: &Vec[UInt8], from: Int, limit: Int) -> Int {
  var i = from;
  while i + 1 < limit {
    if _byte(data, i) == _NATS_CR && _byte(data, i + 1) == _NATS_LF {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first byte equal to `target` in [from, to), or -1.
fn _find_byte(data: &Vec[UInt8], from: Int, to: Int, target: Int) -> Int {
  var i = from;
  while i < to {
    if _byte(data, i) == target {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when data[a, b) is exactly the ASCII literal `lit` (case-sensitive).
fn _span_eq_lit(data: &Vec[UInt8], a: Int, b: Int, lit: Str) -> Bool {
  if b - a != lit.len() {
    return false;
  }
  var i = 0;
  while i < lit.len() {
    if _byte(data, a + i) != ((string.byte_at(lit, i) as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when a[a1, b1) and b[a2, b2) are byte-equal (two different vectors).
fn _span_eq2(a: &Vec[UInt8], a1: Int, b1: Int, b: &Vec[UInt8], a2: Int, b2: Int) -> Bool {
  if b1 - a1 != b2 - a2 {
    return false;
  }
  var i = 0;
  while i < b1 - a1 {
    if _byte(a, a1 + i) != _byte(b, a2 + i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when data[a, b) holds a C0 control byte (below space) or DEL.
fn _span_has_control(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  var i = a;
  while i < b {
    let c = _byte(data, i);
    if c < _NATS_SPACE || c == _NATS_DEL {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Split data[start, end) on single spaces and push the token spans into
// `spans` (two Ints per token). Rejects a leading/trailing space or a double
// space by returning false (spans may then hold the tokens seen so far).
fn _split_tokens(data: &Vec[UInt8], start: Int, end: Int, spans: &mut Vec[Int]) -> Bool {
  var i = start;
  while i < end {
    if _byte(data, i) == _NATS_SPACE {
      return false;
    }
    let ts = i;
    while i < end && _byte(data, i) != _NATS_SPACE {
      i = i + 1;
    }
    spans.push(ts);
    spans.push(i);
    if i < end {
      i = i + 1;
      if i >= end {
        return false;
      }
    }
  }
  return true;
}

// Kind id of the op token data[a, b), or 0 when it is not a known op.
fn _op_kind(data: &Vec[UInt8], a: Int, b: Int) -> Int {
  if _span_eq_lit(data, a, b, "CONNECT") { return _NATS_K_CONNECT; }
  if _span_eq_lit(data, a, b, "PUB") { return _NATS_K_PUB; }
  if _span_eq_lit(data, a, b, "HPUB") { return _NATS_K_HPUB; }
  if _span_eq_lit(data, a, b, "SUB") { return _NATS_K_SUB; }
  if _span_eq_lit(data, a, b, "UNSUB") { return _NATS_K_UNSUB; }
  if _span_eq_lit(data, a, b, "PING") { return _NATS_K_PING; }
  if _span_eq_lit(data, a, b, "PONG") { return _NATS_K_PONG; }
  if _span_eq_lit(data, a, b, "INFO") { return _NATS_K_INFO; }
  if _span_eq_lit(data, a, b, "MSG") { return _NATS_K_MSG; }
  if _span_eq_lit(data, a, b, "HMSG") { return _NATS_K_HMSG; }
  if _span_eq_lit(data, a, b, "+OK") { return _NATS_K_OK; }
  if _span_eq_lit(data, a, b, "-ERR") { return _NATS_K_ERR; }
  return 0;
}

// Parse data[a, b) as a decimal unsigned integer <= cap (leading zeros are
// accepted, '-' is not; no sign). `msg` is the caller's error text.
fn _parse_uint(data: &Vec[UInt8], a: Int, b: Int, cap: Int, msg: Str) -> Result[Int, Str] {
  if a >= b {
    return _err_int(msg);
  }
  let lim = cap / 10;
  let rem = cap % 10;
  var v: Int = 0;
  var i = a;
  while i < b {
    let c = _byte(data, i);
    if c < 48 || c > 57 {
      return _err_int(msg);
    }
    let d = c - 48;
    if v > lim {
      return _err_int(msg);
    }
    if v == lim && d > rem {
      return _err_int(msg);
    }
    v = v * 10 + d;
    i = i + 1;
  }
  return _ok_int(v);
}

// --------------------------------------------------
//  Subjects
// --------------------------------------------------

// True when byte c is allowed inside a literal subject token: printable,
// non-space, not DEL, and not a wildcard ('*' 42 / '>' 62).
fn _subject_char_ok(c: Int) -> Bool {
  if c <= _NATS_SPACE { return false; }
  if c == _NATS_DEL { return false; }
  if c == _NATS_STAR { return false; }
  if c == _NATS_GT { return false; }
  return true;
}

// True when data[a, b) holds a byte a literal subject token may not carry
// (control, space, DEL, '*' or '>').
fn _span_bad_literal(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  var i = a;
  while i < b {
    if !_subject_char_ok(_byte(data, i)) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when data[a, b) holds a '*' or '>' byte anywhere.
fn _span_has_wildcard(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  var i = a;
  while i < b {
    let c = _byte(data, i);
    if c == _NATS_STAR || c == _NATS_GT {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when data[a, b) is a structurally valid subject filter: non-empty,
// '.',-separated tokens with no empty token, where a token that is exactly
// '*' matches any one token and a token that is exactly '>' matches the
// remaining tokens and must be the final token. No control/space/DEL bytes.
fn _filter_span_ok(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  if b <= a {
    return false;
  }
  var i = a;
  while i < b {
    let ts = i;
    while i < b && _byte(data, i) != _NATS_DOT {
      i = i + 1;
    }
    let te = i;
    if te <= ts {
      return false;
    }
    if _span_eq_lit(data, ts, te, ">") {
      if te != b {
        return false;
      }
    } else {
      if !_span_eq_lit(data, ts, te, "*") {
        if _span_bad_literal(data, ts, te) {
          return false;
        }
      }
    }
    if i < b {
      i = i + 1;
      if i >= b {
        return false;
      }
    }
  }
  return true;
}

// True when data[a, b) is a valid literal subject: the filter structure
// without any wildcard byte.
fn _literal_subject_ok(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  if _span_has_wildcard(data, a, b) {
    return false;
  }
  return _filter_span_ok(data, a, b);
}

// Whitelist helpers for whole vectors, used by the encoders.
fn _vec_filter_ok(v: &Vec[UInt8]) -> Bool {
  return _filter_span_ok(v, 0, v.len());
}

fn _vec_literal_ok(v: &Vec[UInt8]) -> Bool {
  return _literal_subject_ok(v, 0, v.len());
}

/// True when `filter` is a structurally valid subject filter for this codec:
/// non-empty, '.'-separated non-empty tokens, '*' wildcard tokens allowed
/// anywhere and '>' allowed only as the whole final token; bytes must be
/// printable and neither space nor DEL. This is a structural check, not a
/// per-server ACL check.
/// Params: filter - the subject/filter bytes.
/// Returns: the predicate.
/// Error case: none. Complexity: O(len(filter)).
pub fn nats_subject_is_valid(filter: &Vec[UInt8]) -> Bool {
  return _vec_filter_ok(filter);
}

/// True when `subject` is a valid literal publish subject for this codec:
/// the nats_subject_is_valid structure with no '*' or '>' anywhere.
/// Params: subject - the subject bytes.
/// Returns: the predicate.
/// Error case: none. Complexity: O(len(subject)).
pub fn nats_publish_subject_is_valid(subject: &Vec[UInt8]) -> Bool {
  return _vec_literal_ok(subject);
}

/// True when literal `subject` matches `filter` under NATS wildcard rules:
/// '*' matches exactly one token, '>' matches one or more remaining tokens,
/// everything else is byte-equal. Both inputs are validated structurally
/// first, so a malformed filter or a wildcard subject yields false.
/// Params: filter - a valid filter (may contain wildcards);
/// subject - a valid literal subject.
/// Returns: the predicate.
/// Error case: none. Complexity: O(len(filter) + len(subject)).
pub fn nats_subject_matches(filter: &Vec[UInt8], subject: &Vec[UInt8]) -> Bool {
  if !_vec_filter_ok(filter) {
    return false;
  }
  if !_vec_literal_ok(subject) {
    return false;
  }
  let flen = filter.len();
  let slen = subject.len();
  var fi = 0;
  var si = 0;
  while fi < flen {
    let fstart = fi;
    while fi < flen && _byte(filter, fi) != _NATS_DOT {
      fi = fi + 1;
    }
    let fend = fi;
    if _span_eq_lit(filter, fstart, fend, ">") {
      return true;
    }
    if si >= slen {
      return false;
    }
    let sstart = si;
    while si < slen && _byte(subject, si) != _NATS_DOT {
      si = si + 1;
    }
    let send = si;
    if !_span_eq_lit(filter, fstart, fend, "*") {
      if !_span_eq2(filter, fstart, fend, subject, sstart, send) {
        return false;
      }
    }
    var fmore = false;
    if fi < flen {
      fi = fi + 1;
      fmore = true;
    }
    var smore = false;
    if si < slen {
      si = si + 1;
      smore = true;
    }
    if fmore != smore {
      return false;
    }
  }
  return si >= slen;
}

// --------------------------------------------------
//  JSON key lookups (INFO / CONNECT subset)
// --------------------------------------------------

// True when data[a, b) looks like a JSON object: at least "{}", first byte
// '{', last byte '}', no control bytes (spaces are fine).
fn _json_span_ok(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  if b - a < 2 {
    return false;
  }
  if _byte(data, a) != _NATS_LBRACE {
    return false;
  }
  if _byte(data, b - 1) != _NATS_RBRACE {
    return false;
  }
  if _span_has_control(data, a, b) {
    return false;
  }
  return true;
}

fn _vec_json_ok(v: &Vec[UInt8]) -> Bool {
  return _json_span_ok(v, 0, v.len());
}

// True when the quoted key `key` starts right after the opening quote that
// precedes `kstart` (i.e. text[kstart, kstart+key.len()) == key and the next
// byte is a closing quote).
fn _json_key_matches(text: &Vec[UInt8], kstart: Int, key: Str) -> Bool {
  if kstart + key.len() >= text.len() {
    return false;
  }
  var i = 0;
  while i < key.len() {
    if _byte(text, kstart + i) != ((string.byte_at(key, i) as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return _byte(text, kstart + key.len()) == _NATS_QUOTE;
}

// Span of the first scalar value of the top-level member `key` in the object
// text: (start, end) with the quotes included for string values. Keys are
// only recognised at an object boundary (start, after '{', ',', or
// whitespace), so a key text inside a string value does not match. Composite
// values ({...}/[...]) yield Err("nats: json bad value: <key>"); a missing
// key yields Err("nats: json key not found: <key>").
fn _json_find(text: &Vec[UInt8], key: Str) -> Result[(Int, Int), Str] {
  if key.len() == 0 {
    return _err_pair("nats: json empty key");
  }
  let n = text.len();
  var i = 0;
  while i < n {
    if _byte(text, i) == _NATS_QUOTE {
      var boundary = false;
      if i == 0 {
        boundary = true;
      } else {
        let before = _byte(text, i - 1);
        if before == _NATS_LBRACE || before == _NATS_COMMA || before == _NATS_SPACE {
          boundary = true;
        }
        if before == _NATS_CR || before == _NATS_LF || before == _NATS_TAB {
          boundary = true;
        }
      }
      if boundary && _json_key_matches(text, i + 1, key) {
        var j = i + 2 + key.len();
        while j < n && _byte(text, j) == _NATS_SPACE {
          j = j + 1;
        }
        if j < n && _byte(text, j) == _NATS_COLON {
          j = j + 1;
          while j < n && _byte(text, j) == _NATS_SPACE {
            j = j + 1;
          }
          if j >= n {
            return _err_pair("nats: json bad value: " + key);
          }
          let vs = j;
          let vc = _byte(text, j);
          if vc == _NATS_QUOTE {
            j = j + 1;
            var closed = false;
            while j < n {
              let c = _byte(text, j);
              if c == _NATS_BACKSLASH {
                j = j + 2;
              } elif c == _NATS_QUOTE {
                closed = true;
                j = j + 1;
                break;
              } else {
                j = j + 1;
              }
            }
            if !closed {
              return _err_pair("nats: json bad value: " + key);
            }
            return _ok_pair((vs, j));
          }
          if vc == _NATS_LBRACE || vc == _NATS_LBRACKET {
            return _err_pair("nats: json bad value: " + key);
          }
          while j < n {
            let c = _byte(text, j);
            if c == _NATS_COMMA || c == _NATS_RBRACE || c == _NATS_LBRACKET {
              break;
            }
            if c == _NATS_SPACE || c == _NATS_CR || c == _NATS_LF {
              break;
            }
            j = j + 1;
          }
          if j == vs {
            return _err_pair("nats: json bad value: " + key);
          }
          return _ok_pair((vs, j));
        }
      }
    }
    i = i + 1;
  }
  return _err_pair("nats: json key not found: " + key);
}

/// True when the object text carries a scalar top-level member `key`.
/// Params: text - a JSON object as raw bytes; key - the member name.
/// Returns: the predicate (false for a missing key and for composite values).
/// Error case: none. Complexity: O(len(text)).
pub fn nats_json_has(text: &Vec[UInt8], key: Str) -> Bool {
  let r = _json_find(text, key);
  return r.is_ok;
}

/// Raw bytes of the string value of top-level member `key` (quotes stripped,
/// escapes left as written -- no unescaping).
/// Params: text - a JSON object as raw bytes; key - the member name.
/// Returns: Ok(inner bytes) for a string member.
/// Error case: Err("nats: json key not found: <key>") or
/// Err("nats: json bad value: <key>") for a non-string value;
/// Err("nats: json empty key") for an empty key.
/// Complexity: O(len(text)).
pub fn nats_json_str(text: &Vec[UInt8], key: Str) -> Result[Vec[UInt8], Str] {
  let r = _json_find(text, key);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  let span = r.value;
  let a: Int = span.0;
  let b: Int = span.1;
  if b - a < 2 {
    return _err_bytes("nats: json bad value: " + key);
  }
  if _byte(text, a) != _NATS_QUOTE {
    return _err_bytes("nats: json bad value: " + key);
  }
  var out = Vec[UInt8].new();
  _copy_span(text, a + 1, b - 1, &mut out);
  return _ok_bytes(out);
}

/// Integer value of the top-level member `key`.
/// Params: text - a JSON object as raw bytes; key - the member name.
/// Returns: Ok(value) for a decimal integer member (optional '-', value
/// magnitude at most 2147483647).
/// Error case: Err("nats: json key not found: <key>") or
/// Err("nats: json bad value: <key>") for a non-integer value, an empty key
/// or an out-of-range magnitude. Complexity: O(len(text)).
pub fn nats_json_int(text: &Vec[UInt8], key: Str) -> Result[Int, Str] {
  let r = _json_find(text, key);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let span = r.value;
  let a: Int = span.0;
  let b: Int = span.1;
  var i = a;
  var neg = false;
  if _byte(text, i) == _NATS_DASH {
    neg = true;
    i = i + 1;
  }
  if i >= b {
    return _err_int("nats: json bad value: " + key);
  }
  let lim = _NATS_MAX_SIZE / 10;
  let rem = _NATS_MAX_SIZE % 10;
  var v: Int = 0;
  while i < b {
    let c = _byte(text, i);
    if c < 48 || c > 57 {
      return _err_int("nats: json bad value: " + key);
    }
    let d = c - 48;
    if v > lim {
      return _err_int("nats: json bad value: " + key);
    }
    if v == lim && d > rem {
      return _err_int("nats: json bad value: " + key);
    }
    v = v * 10 + d;
    i = i + 1;
  }
  if neg {
    return _ok_int(0 - v);
  }
  return _ok_int(v);
}

/// Boolean value of the top-level member `key`.
/// Params: text - a JSON object as raw bytes; key - the member name.
/// Returns: Ok(true)/Ok(false) for a true/false member.
/// Error case: Err("nats: json key not found: <key>") or
/// Err("nats: json bad value: <key>") for any other value.
/// Complexity: O(len(text)).
pub fn nats_json_bool(text: &Vec[UInt8], key: Str) -> Result[Bool, Str] {
  let r = _json_find(text, key);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let span = r.value;
  let a: Int = span.0;
  let b: Int = span.1;
  if _span_eq_lit(text, a, b, "true") {
    return _ok_bool(true);
  }
  if _span_eq_lit(text, a, b, "false") {
    return _ok_bool(false);
  }
  return _err_bool("nats: json bad value: " + key);
}

// --------------------------------------------------
//  Encoders
// --------------------------------------------------

// "CONNECT <json>\r\n" / "INFO <json>\r\n".
fn _encode_json_op(name: Str, json: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if !_vec_json_ok(json) {
    return _err_bytes("nats: bad json");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, name);
  _push_space(&mut out);
  _push_vec(&mut out, json);
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode a CONNECT op: "CONNECT <json>\r\n".
/// Params: json - a JSON object as raw bytes ("{}" or with members).
/// Returns: Ok(wire bytes).
/// Error case: Err("nats: bad json") when json is not a braced object without
/// control bytes. Complexity: O(len(json)).
pub fn nats_encode_connect(json: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return _encode_json_op("CONNECT", json);
}

/// Encode an INFO op: "INFO <json>\r\n".
/// Params: json - a JSON object as raw bytes.
/// Returns: Ok(wire bytes).
/// Error case: Err("nats: bad json") when json is not a braced object without
/// control bytes. Complexity: O(len(json)).
pub fn nats_encode_info(json: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return _encode_json_op("INFO", json);
}

/// Encode a PUB op: "PUB <subject> [reply] <size>\r\n<payload>\r\n". The
/// payload is written verbatim (NULs and any byte >= 128 included).
/// Params: subject - literal subject; reply - optional reply-to ("" omits);
/// payload - raw payload bytes.
/// Returns: Ok(wire bytes).
/// Error case: Err("nats: bad subject"), Err("nats: bad reply") for invalid
/// subjects, Err("nats: payload too long") above 2147483647 bytes.
/// Complexity: O(packet size).
pub fn nats_encode_pub(subject: &Vec[UInt8], reply: &Vec[UInt8], payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if !_vec_literal_ok(subject) {
    return _err_bytes("nats: bad subject");
  }
  if reply.len() > 0 {
    if !_vec_literal_ok(reply) {
      return _err_bytes("nats: bad reply");
    }
  }
  if payload.len() > _NATS_MAX_SIZE {
    return _err_bytes("nats: payload too long");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "PUB ");
  _push_vec(&mut out, subject);
  if reply.len() > 0 {
    _push_space(&mut out);
    _push_vec(&mut out, reply);
  }
  _push_space(&mut out);
  builder.sb_push_int(&mut out, payload.len());
  _push_crlf(&mut out);
  _push_vec(&mut out, payload);
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode an HPUB op: "HPUB <subject> [reply] <header_size> <total_size>\r\n
/// <headers><payload>\r\n". The header block must be a NATS/1.0 block
/// (starts with "NATS/1.0" + CRLF or SP, ends with CRLF CRLF); total_size is
/// header_size + payload len.
/// Params: subject - literal subject; reply - optional reply-to ("" omits);
/// headers - the header block; payload - raw payload bytes.
/// Returns: Ok(wire bytes).
/// Error case: Err("nats: bad subject"), Err("nats: bad reply"),
/// Err("nats: bad headers"), Err("nats: payload too long").
/// Complexity: O(packet size).
pub fn nats_encode_hpub(subject: &Vec[UInt8], reply: &Vec[UInt8], headers: &Vec[UInt8], payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if !_vec_literal_ok(subject) {
    return _err_bytes("nats: bad subject");
  }
  if reply.len() > 0 {
    if !_vec_literal_ok(reply) {
      return _err_bytes("nats: bad reply");
    }
  }
  if !_vec_headers_ok(headers) {
    return _err_bytes("nats: bad headers");
  }
  let hs = headers.len();
  let ts = hs + payload.len();
  if ts > _NATS_MAX_SIZE {
    return _err_bytes("nats: payload too long");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "HPUB ");
  _push_vec(&mut out, subject);
  if reply.len() > 0 {
    _push_space(&mut out);
    _push_vec(&mut out, reply);
  }
  _push_space(&mut out);
  builder.sb_push_int(&mut out, hs);
  _push_space(&mut out);
  builder.sb_push_int(&mut out, ts);
  _push_crlf(&mut out);
  _push_vec(&mut out, headers);
  _push_vec(&mut out, payload);
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode a SUB op: "SUB <subject> [queue] <sid>\r\n". The subject may carry
/// '*'/'>' wildcards.
/// Params: subject - a valid filter; queue - optional queue group ("" omits);
/// sid - stream id, 1..2147483647.
/// Returns: Ok(wire bytes).
/// Error case: Err("nats: bad subject"), Err("nats: bad queue"),
/// Err("nats: bad sid"). Complexity: O(len(packet)).
pub fn nats_encode_sub(subject: &Vec[UInt8], queue: &Vec[UInt8], sid: Int) -> Result[Vec[UInt8], Str] {
  if !_vec_filter_ok(subject) {
    return _err_bytes("nats: bad subject");
  }
  if queue.len() > 0 {
    if !_vec_literal_ok(queue) {
      return _err_bytes("nats: bad queue");
    }
  }
  if sid < 1 || sid > _NATS_MAX_SIZE {
    return _err_bytes("nats: bad sid");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "SUB ");
  _push_vec(&mut out, subject);
  if queue.len() > 0 {
    _push_space(&mut out);
    _push_vec(&mut out, queue);
  }
  _push_space(&mut out);
  builder.sb_push_int(&mut out, sid);
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode an UNSUB op: "UNSUB <sid>\r\n" or "UNSUB <sid> <max_msgs>\r\n"
/// when max_msgs is positive.
/// Params: sid - stream id, 1..2147483647; max_msgs - auto-unsubscribe count
/// (0 omits it).
/// Returns: Ok(wire bytes).
/// Error case: Err("nats: bad sid"), Err("nats: bad max").
/// Complexity: O(1).
pub fn nats_encode_unsub(sid: Int, max_msgs: Int) -> Result[Vec[UInt8], Str] {
  if sid < 1 || sid > _NATS_MAX_SIZE {
    return _err_bytes("nats: bad sid");
  }
  if max_msgs < 0 || max_msgs > _NATS_MAX_SIZE {
    return _err_bytes("nats: bad max");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "UNSUB ");
  builder.sb_push_int(&mut out, sid);
  if max_msgs > 0 {
    _push_space(&mut out);
    builder.sb_push_int(&mut out, max_msgs);
  }
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode a MSG op: "MSG <subject> <sid> [reply] <size>\r\n<payload>\r\n".
/// Params: subject - literal subject; sid - stream id, 1..2147483647;
/// reply - optional reply-to ("" omits); payload - raw payload bytes.
/// Returns: Ok(wire bytes).
/// Error case: Err("nats: bad subject"), Err("nats: bad sid"),
/// Err("nats: bad reply"), Err("nats: payload too long").
/// Complexity: O(packet size).
pub fn nats_encode_msg(subject: &Vec[UInt8], sid: Int, reply: &Vec[UInt8], payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if !_vec_literal_ok(subject) {
    return _err_bytes("nats: bad subject");
  }
  if sid < 1 || sid > _NATS_MAX_SIZE {
    return _err_bytes("nats: bad sid");
  }
  if reply.len() > 0 {
    if !_vec_literal_ok(reply) {
      return _err_bytes("nats: bad reply");
    }
  }
  if payload.len() > _NATS_MAX_SIZE {
    return _err_bytes("nats: payload too long");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "MSG ");
  _push_vec(&mut out, subject);
  _push_space(&mut out);
  builder.sb_push_int(&mut out, sid);
  if reply.len() > 0 {
    _push_space(&mut out);
    _push_vec(&mut out, reply);
  }
  _push_space(&mut out);
  builder.sb_push_int(&mut out, payload.len());
  _push_crlf(&mut out);
  _push_vec(&mut out, payload);
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode an HMSG op: "HMSG <subject> <sid> [reply] <header_size>
/// <total_size>\r\n<headers><payload>\r\n".
/// Params: subject - literal subject; sid - stream id, 1..2147483647;
/// reply - optional reply-to ("" omits); headers - a NATS/1.0 header block;
/// payload - raw payload bytes.
/// Returns: Ok(wire bytes).
/// Error case: Err("nats: bad subject"), Err("nats: bad sid"),
/// Err("nats: bad reply"), Err("nats: bad headers"),
/// Err("nats: payload too long"). Complexity: O(packet size).
pub fn nats_encode_hmsg(subject: &Vec[UInt8], sid: Int, reply: &Vec[UInt8], headers: &Vec[UInt8], payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if !_vec_literal_ok(subject) {
    return _err_bytes("nats: bad subject");
  }
  if sid < 1 || sid > _NATS_MAX_SIZE {
    return _err_bytes("nats: bad sid");
  }
  if reply.len() > 0 {
    if !_vec_literal_ok(reply) {
      return _err_bytes("nats: bad reply");
    }
  }
  if !_vec_headers_ok(headers) {
    return _err_bytes("nats: bad headers");
  }
  let hs = headers.len();
  let ts = hs + payload.len();
  if ts > _NATS_MAX_SIZE {
    return _err_bytes("nats: payload too long");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "HMSG ");
  _push_vec(&mut out, subject);
  _push_space(&mut out);
  builder.sb_push_int(&mut out, sid);
  if reply.len() > 0 {
    _push_space(&mut out);
    _push_vec(&mut out, reply);
  }
  _push_space(&mut out);
  builder.sb_push_int(&mut out, hs);
  _push_space(&mut out);
  builder.sb_push_int(&mut out, ts);
  _push_crlf(&mut out);
  _push_vec(&mut out, headers);
  _push_vec(&mut out, payload);
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode a -ERR op: "-ERR <message>\r\n".
/// Params: message - the error text (must be non-empty and control-free;
/// spaces are fine).
/// Returns: Ok(wire bytes).
/// Error case: Err("nats: bad error text").
/// Complexity: O(len(message)).
pub fn nats_encode_err(message: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if message.len() == 0 {
    return _err_bytes("nats: bad error text");
  }
  if _span_has_control(message, 0, message.len()) {
    return _err_bytes("nats: bad error text");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "-ERR ");
  _push_vec(&mut out, message);
  _push_crlf(&mut out);
  return _ok_bytes(out);
}

/// Encode the +OK op ("+OK\r\n"). Params: none. Returns: the wire bytes.
pub fn nats_encode_ok() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "+OK");
  _push_crlf(&mut out);
  return out;
}

/// Encode the PING op ("PING\r\n"). Params: none. Returns: the wire bytes.
pub fn nats_encode_ping() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "PING");
  _push_crlf(&mut out);
  return out;
}

/// Encode the PONG op ("PONG\r\n"). Params: none. Returns: the wire bytes.
pub fn nats_encode_pong() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "PONG");
  _push_crlf(&mut out);
  return out;
}

// --------------------------------------------------
//  Header block (HPUB / HMSG)
// --------------------------------------------------

// True when data[a, b) is a NATS/1.0 header block: at least the version line
// "NATS/1.0" plus CRLF CRLF (12 bytes), the 9th byte CR (then LF) or SP, and
// the last four bytes CR LF CR LF.
fn _headers_span_ok(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  if b - a < 12 {
    return false;
  }
  if !_span_eq_lit(data, a, a + 8, "NATS/1.0") {
    return false;
  }
  let c = _byte(data, a + 8);
  if c == _NATS_CR {
    if _byte(data, a + 9) != _NATS_LF {
      return false;
    }
  } elif c != _NATS_SPACE {
    return false;
  }
  if _byte(data, b - 4) != _NATS_CR {
    return false;
  }
  if _byte(data, b - 3) != _NATS_LF {
    return false;
  }
  if _byte(data, b - 2) != _NATS_CR {
    return false;
  }
  if _byte(data, b - 1) != _NATS_LF {
    return false;
  }
  return true;
}

fn _vec_headers_ok(v: &Vec[UInt8]) -> Bool {
  return _headers_span_ok(v, 0, v.len());
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

// Fresh op of `kind` with every other field empty/zero and `consumed` set.
fn _empty_op(kind: Int, consumed: Int) -> NatsOp {
  return NatsOp{
    kind: kind;
    subject: Vec[UInt8].new();
    reply: Vec[UInt8].new();
    queue: Vec[UInt8].new();
    sid: 0;
    max_msgs: 0;
    header_size: 0;
    total_size: 0;
    payload: Vec[UInt8].new();
    headers: Vec[UInt8].new();
    text: Vec[UInt8].new();
    consumed: consumed;
  };
}

// CONNECT/INFO: the argument span [a, b) must be a braced JSON object.
fn _parse_json_op(data: &Vec[UInt8], kind: Int, off: Int, cr: Int, a: Int, b: Int) -> Result[NatsOp, Str] {
  if a >= b {
    return _err_op(_at("nats: bad args", off));
  }
  if !_json_span_ok(data, a, b) {
    return _err_op(_at("nats: bad json", off));
  }
  var text = Vec[UInt8].new();
  _copy_span(data, a, b, &mut text);
  var op = _empty_op(kind, cr + 2 - off);
  op.text = text;
  return _ok_op(op);
}

// -ERR: the message span [a, b) must be non-empty and control-free.
fn _parse_err_op(data: &Vec[UInt8], off: Int, cr: Int, a: Int, b: Int) -> Result[NatsOp, Str] {
  if a >= b {
    return _err_op(_at("nats: bad args", off));
  }
  if _span_has_control(data, a, b) {
    return _err_op(_at("nats: bad args", off));
  }
  var text = Vec[UInt8].new();
  _copy_span(data, a, b, &mut text);
  var op = _empty_op(_NATS_K_ERR, cr + 2 - off);
  op.text = text;
  return _ok_op(op);
}

// PUB <subject> [reply] <size>: literal subject/reply, bounded size, then
// exactly `size` payload bytes and CRLF.
fn _parse_pub_op(data: &Vec[UInt8], off: Int, cr: Int, spans: &Vec[Int]) -> Result[NatsOp, Str] {
  let tcount = spans.len() / 2;
  if tcount != 2 && tcount != 3 {
    return _err_op(_at("nats: bad args", off));
  }
  let s1: Int = spans[0];
  let e1: Int = spans[1];
  if !_literal_subject_ok(data, s1, e1) {
    return _err_op(_at("nats: bad subject", off));
  }
  var reply = Vec[UInt8].new();
  var idx = 2;
  if tcount == 3 {
    let s2: Int = spans[2];
    let e2: Int = spans[3];
    if !_literal_subject_ok(data, s2, e2) {
      return _err_op(_at("nats: bad reply", off));
    }
    _copy_span(data, s2, e2, &mut reply);
    idx = 4;
  }
  let ss: Int = spans[idx];
  let se: Int = spans[idx + 1];
  let pr = _parse_uint(data, ss, se, _NATS_MAX_SIZE, "nats: bad size");
  if !pr.is_ok {
    return _err_op(_at(pr.error, off));
  }
  let size: Int = pr.value;
  let pstart = cr + 2;
  let total = data.len();
  if pstart + size + 2 > total {
    return _err_op(_at("nats: truncated payload", off));
  }
  if _byte(data, pstart + size) != _NATS_CR || _byte(data, pstart + size + 1) != _NATS_LF {
    return _err_op(_at("nats: bad payload terminator", off));
  }
  var subject = Vec[UInt8].new();
  _copy_span(data, s1, e1, &mut subject);
  var payload = Vec[UInt8].new();
  _copy_span(data, pstart, pstart + size, &mut payload);
  var op = _empty_op(_NATS_K_PUB, pstart + size + 2 - off);
  op.subject = subject;
  op.reply = reply;
  op.total_size = size;
  op.payload = payload;
  return _ok_op(op);
}

// HPUB <subject> [reply] <header_size> <total_size>: header_size must not
// exceed total_size, the header block must be a NATS/1.0 block and the
// payload part is total_size - header_size bytes; CRLF closes the packet.
fn _parse_hpub_op(data: &Vec[UInt8], off: Int, cr: Int, spans: &Vec[Int]) -> Result[NatsOp, Str] {
  let tcount = spans.len() / 2;
  if tcount != 3 && tcount != 4 {
    return _err_op(_at("nats: bad args", off));
  }
  let s1: Int = spans[0];
  let e1: Int = spans[1];
  if !_literal_subject_ok(data, s1, e1) {
    return _err_op(_at("nats: bad subject", off));
  }
  var reply = Vec[UInt8].new();
  var idx = 2;
  if tcount == 4 {
    let s2: Int = spans[2];
    let e2: Int = spans[3];
    if !_literal_subject_ok(data, s2, e2) {
      return _err_op(_at("nats: bad reply", off));
    }
    _copy_span(data, s2, e2, &mut reply);
    idx = 4;
  }
  let hs0: Int = spans[idx];
  let he0: Int = spans[idx + 1];
  let ts0: Int = spans[idx + 2];
  let te0: Int = spans[idx + 3];
  let hpr = _parse_uint(data, hs0, he0, _NATS_MAX_SIZE, "nats: bad size");
  if !hpr.is_ok {
    return _err_op(_at(hpr.error, off));
  }
  let tpr = _parse_uint(data, ts0, te0, _NATS_MAX_SIZE, "nats: bad size");
  if !tpr.is_ok {
    return _err_op(_at(tpr.error, off));
  }
  let hs: Int = hpr.value;
  let ts: Int = tpr.value;
  if hs > ts {
    return _err_op(_at("nats: bad size", off));
  }
  let pstart = cr + 2;
  let total = data.len();
  if pstart + ts + 2 > total {
    return _err_op(_at("nats: truncated payload", off));
  }
  if _byte(data, pstart + ts) != _NATS_CR || _byte(data, pstart + ts + 1) != _NATS_LF {
    return _err_op(_at("nats: bad payload terminator", off));
  }
  if !_headers_span_ok(data, pstart, pstart + hs) {
    return _err_op(_at("nats: bad headers", off));
  }
  var subject = Vec[UInt8].new();
  _copy_span(data, s1, e1, &mut subject);
  var headers = Vec[UInt8].new();
  _copy_span(data, pstart, pstart + hs, &mut headers);
  var payload = Vec[UInt8].new();
  _copy_span(data, pstart + hs, pstart + ts, &mut payload);
  var op = _empty_op(_NATS_K_HPUB, pstart + ts + 2 - off);
  op.subject = subject;
  op.reply = reply;
  op.header_size = hs;
  op.total_size = ts;
  op.headers = headers;
  op.payload = payload;
  return _ok_op(op);
}

// SUB <subject> [queue] <sid>: a filter subject, an optional literal queue
// group and a positive stream id.
fn _parse_sub_op(data: &Vec[UInt8], off: Int, cr: Int, spans: &Vec[Int]) -> Result[NatsOp, Str] {
  let tcount = spans.len() / 2;
  if tcount != 2 && tcount != 3 {
    return _err_op(_at("nats: bad args", off));
  }
  let s1: Int = spans[0];
  let e1: Int = spans[1];
  if !_filter_span_ok(data, s1, e1) {
    return _err_op(_at("nats: bad subject", off));
  }
  var queue = Vec[UInt8].new();
  var idx = 2;
  if tcount == 3 {
    let s2: Int = spans[2];
    let e2: Int = spans[3];
    if !_literal_subject_ok(data, s2, e2) {
      return _err_op(_at("nats: bad queue", off));
    }
    _copy_span(data, s2, e2, &mut queue);
    idx = 4;
  }
  let ss: Int = spans[idx];
  let se: Int = spans[idx + 1];
  let pr = _parse_uint(data, ss, se, _NATS_MAX_SIZE, "nats: bad sid");
  if !pr.is_ok {
    return _err_op(_at(pr.error, off));
  }
  let sid: Int = pr.value;
  if sid < 1 {
    return _err_op(_at("nats: bad sid", off));
  }
  var subject = Vec[UInt8].new();
  _copy_span(data, s1, e1, &mut subject);
  var op = _empty_op(_NATS_K_SUB, cr + 2 - off);
  op.subject = subject;
  op.queue = queue;
  op.sid = sid;
  return _ok_op(op);
}

// UNSUB <sid> [max_msgs]: positive stream id and, when present, a positive
// max_msgs.
fn _parse_unsub_op(data: &Vec[UInt8], off: Int, cr: Int, spans: &Vec[Int]) -> Result[NatsOp, Str] {
  let tcount = spans.len() / 2;
  if tcount != 1 && tcount != 2 {
    return _err_op(_at("nats: bad args", off));
  }
  let s1: Int = spans[0];
  let e1: Int = spans[1];
  let pr = _parse_uint(data, s1, e1, _NATS_MAX_SIZE, "nats: bad sid");
  if !pr.is_ok {
    return _err_op(_at(pr.error, off));
  }
  let sid: Int = pr.value;
  if sid < 1 {
    return _err_op(_at("nats: bad sid", off));
  }
  var max_msgs: Int = 0;
  if tcount == 2 {
    let s2: Int = spans[2];
    let e2: Int = spans[3];
    let mr = _parse_uint(data, s2, e2, _NATS_MAX_SIZE, "nats: bad max");
    if !mr.is_ok {
      return _err_op(_at(mr.error, off));
    }
    max_msgs = mr.value;
    if max_msgs < 1 {
      return _err_op(_at("nats: bad max", off));
    }
  }
  var op = _empty_op(_NATS_K_UNSUB, cr + 2 - off);
  op.sid = sid;
  op.max_msgs = max_msgs;
  return _ok_op(op);
}

// MSG <subject> <sid> [reply] <size>: same payload framing as PUB.
fn _parse_msg_op(data: &Vec[UInt8], off: Int, cr: Int, spans: &Vec[Int]) -> Result[NatsOp, Str] {
  let tcount = spans.len() / 2;
  if tcount != 3 && tcount != 4 {
    return _err_op(_at("nats: bad args", off));
  }
  let s1: Int = spans[0];
  let e1: Int = spans[1];
  if !_literal_subject_ok(data, s1, e1) {
    return _err_op(_at("nats: bad subject", off));
  }
  let ds: Int = spans[2];
  let de: Int = spans[3];
  let sr = _parse_uint(data, ds, de, _NATS_MAX_SIZE, "nats: bad sid");
  if !sr.is_ok {
    return _err_op(_at(sr.error, off));
  }
  let sid: Int = sr.value;
  if sid < 1 {
    return _err_op(_at("nats: bad sid", off));
  }
  var reply = Vec[UInt8].new();
  var idx = 4;
  if tcount == 4 {
    let s3: Int = spans[4];
    let e3: Int = spans[5];
    if !_literal_subject_ok(data, s3, e3) {
      return _err_op(_at("nats: bad reply", off));
    }
    _copy_span(data, s3, e3, &mut reply);
    idx = 6;
  }
  let ss: Int = spans[idx];
  let se: Int = spans[idx + 1];
  let pr = _parse_uint(data, ss, se, _NATS_MAX_SIZE, "nats: bad size");
  if !pr.is_ok {
    return _err_op(_at(pr.error, off));
  }
  let size: Int = pr.value;
  let pstart = cr + 2;
  let total = data.len();
  if pstart + size + 2 > total {
    return _err_op(_at("nats: truncated payload", off));
  }
  if _byte(data, pstart + size) != _NATS_CR || _byte(data, pstart + size + 1) != _NATS_LF {
    return _err_op(_at("nats: bad payload terminator", off));
  }
  var subject = Vec[UInt8].new();
  _copy_span(data, s1, e1, &mut subject);
  var payload = Vec[UInt8].new();
  _copy_span(data, pstart, pstart + size, &mut payload);
  var op = _empty_op(_NATS_K_MSG, pstart + size + 2 - off);
  op.subject = subject;
  op.reply = reply;
  op.sid = sid;
  op.total_size = size;
  op.payload = payload;
  return _ok_op(op);
}

// HMSG <subject> <sid> [reply] <header_size> <total_size>: same framing as
// HPUB with a stream id.
fn _parse_hmsg_op(data: &Vec[UInt8], off: Int, cr: Int, spans: &Vec[Int]) -> Result[NatsOp, Str] {
  let tcount = spans.len() / 2;
  if tcount != 4 && tcount != 5 {
    return _err_op(_at("nats: bad args", off));
  }
  let s1: Int = spans[0];
  let e1: Int = spans[1];
  if !_literal_subject_ok(data, s1, e1) {
    return _err_op(_at("nats: bad subject", off));
  }
  let ds: Int = spans[2];
  let de: Int = spans[3];
  let sr = _parse_uint(data, ds, de, _NATS_MAX_SIZE, "nats: bad sid");
  if !sr.is_ok {
    return _err_op(_at(sr.error, off));
  }
  let sid: Int = sr.value;
  if sid < 1 {
    return _err_op(_at("nats: bad sid", off));
  }
  var reply = Vec[UInt8].new();
  var idx = 4;
  if tcount == 5 {
    let s3: Int = spans[4];
    let e3: Int = spans[5];
    if !_literal_subject_ok(data, s3, e3) {
      return _err_op(_at("nats: bad reply", off));
    }
    _copy_span(data, s3, e3, &mut reply);
    idx = 6;
  }
  let hs0: Int = spans[idx];
  let he0: Int = spans[idx + 1];
  let ts0: Int = spans[idx + 2];
  let te0: Int = spans[idx + 3];
  let hpr = _parse_uint(data, hs0, he0, _NATS_MAX_SIZE, "nats: bad size");
  if !hpr.is_ok {
    return _err_op(_at(hpr.error, off));
  }
  let tpr = _parse_uint(data, ts0, te0, _NATS_MAX_SIZE, "nats: bad size");
  if !tpr.is_ok {
    return _err_op(_at(tpr.error, off));
  }
  let hs: Int = hpr.value;
  let ts: Int = tpr.value;
  if hs > ts {
    return _err_op(_at("nats: bad size", off));
  }
  let pstart = cr + 2;
  let total = data.len();
  if pstart + ts + 2 > total {
    return _err_op(_at("nats: truncated payload", off));
  }
  if _byte(data, pstart + ts) != _NATS_CR || _byte(data, pstart + ts + 1) != _NATS_LF {
    return _err_op(_at("nats: bad payload terminator", off));
  }
  if !_headers_span_ok(data, pstart, pstart + hs) {
    return _err_op(_at("nats: bad headers", off));
  }
  var subject = Vec[UInt8].new();
  _copy_span(data, s1, e1, &mut subject);
  var headers = Vec[UInt8].new();
  _copy_span(data, pstart, pstart + hs, &mut headers);
  var payload = Vec[UInt8].new();
  _copy_span(data, pstart + hs, pstart + ts, &mut payload);
  var op = _empty_op(_NATS_K_HMSG, pstart + ts + 2 - off);
  op.subject = subject;
  op.reply = reply;
  op.sid = sid;
  op.header_size = hs;
  op.total_size = ts;
  op.headers = headers;
  op.payload = payload;
  return _ok_op(op);
}

/// Parse exactly one protocol op starting at byte offset `off`.
/// Params: data - the receive buffer (may hold several ops); off - the byte
/// offset of the op start.
/// Grammar: one CRLF-terminated control line (at most 4096 bytes including
/// CRLF), then for PUB/HPUB/MSG/HMSG exactly the declared number of payload
/// bytes and a closing CRLF. Payload bytes are copied verbatim, so they may
/// contain NUL, CR, LF and bytes >= 128. Subjects are validated structurally
/// (PUB/MSG literal, SUB filters may use '*'/'>'); CONNECT/INFO require a
/// braced JSON object; -ERR requires a non-empty control-free message.
/// Returns: Ok(op) where op.consumed is the number of bytes to advance
/// (control line + payload + closing CRLF); the first op starts at `off + 0`.
/// Error case: Err("nats: negative offset at <off>") for off < 0;
/// Err("nats: truncated op at <off>") without CRLF (or with too few bytes);
/// Err("nats: control line too long at <off>") past 4096 bytes;
/// Err("nats: unknown op at <off>") for an unknown op token;
/// Err("nats: bad args at <off>"), Err("nats: bad subject at <off>"),
/// Err("nats: bad reply at <off>"), Err("nats: bad queue at <off>"),
/// Err("nats: bad sid at <off>"), Err("nats: bad max at <off>"),
/// Err("nats: bad size at <off>"), Err("nats: bad headers at <off>"),
/// Err("nats: bad json at <off>"), Err("nats: truncated payload at <off>"),
/// Err("nats: bad payload terminator at <off>") for malformed ops.
/// Complexity: O(op size).
pub fn nats_parse_op(data: &Vec[UInt8], off: Int) -> Result[NatsOp, Str] {
  if off < 0 {
    return _err_op(_at("nats: negative offset", off));
  }
  let total = data.len();
  if off >= total {
    return _err_op(_at("nats: truncated op", off));
  }
  var lim: Int = total;
  if off + _NATS_MAX_CONTROL < lim {
    lim = off + _NATS_MAX_CONTROL;
  }
  let cr = _find_crlf(data, off, lim);
  if cr < 0 {
    if lim - off >= _NATS_MAX_CONTROL {
      return _err_op(_at("nats: control line too long", off));
    }
    return _err_op(_at("nats: truncated op", off));
  }
  if cr + 2 - off > _NATS_MAX_CONTROL {
    return _err_op(_at("nats: control line too long", off));
  }
  let line_end = cr;
  let sp = _find_byte(data, off, line_end, _NATS_SPACE);
  var op_end = line_end;
  if sp >= 0 {
    op_end = sp;
  }
  if op_end <= off {
    return _err_op(_at("nats: unknown op", off));
  }
  let kind = _op_kind(data, off, op_end);
  if kind == 0 {
    return _err_op(_at("nats: unknown op", off));
  }
  if sp < 0 {
    if kind == _NATS_K_PING {
      return _ok_op(_empty_op(_NATS_K_PING, 6));
    }
    if kind == _NATS_K_PONG {
      return _ok_op(_empty_op(_NATS_K_PONG, 6));
    }
    if kind == _NATS_K_OK {
      return _ok_op(_empty_op(_NATS_K_OK, 5));
    }
    return _err_op(_at("nats: bad args", off));
  }
  if kind == _NATS_K_CONNECT || kind == _NATS_K_INFO {
    return _parse_json_op(data, kind, off, cr, sp + 1, line_end);
  }
  if kind == _NATS_K_ERR {
    return _parse_err_op(data, off, cr, sp + 1, line_end);
  }
  if kind == _NATS_K_PING || kind == _NATS_K_PONG || kind == _NATS_K_OK {
    return _err_op(_at("nats: bad args", off));
  }
  var spans = Vec[Int].new();
  if !_split_tokens(data, sp + 1, line_end, &mut spans) {
    return _err_op(_at("nats: bad args", off));
  }
  if kind == _NATS_K_PUB {
    return _parse_pub_op(data, off, cr, &spans);
  }
  if kind == _NATS_K_HPUB {
    return _parse_hpub_op(data, off, cr, &spans);
  }
  if kind == _NATS_K_SUB {
    return _parse_sub_op(data, off, cr, &spans);
  }
  if kind == _NATS_K_UNSUB {
    return _parse_unsub_op(data, off, cr, &spans);
  }
  if kind == _NATS_K_MSG {
    return _parse_msg_op(data, off, cr, &spans);
  }
  return _parse_hmsg_op(data, off, cr, &spans);
}
