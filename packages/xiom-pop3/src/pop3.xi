// XIOM -- xiom.pop3: POP3 protocol codec (RFC 1939)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM, in-memory codec for the Post Office Protocol version 3
// (RFC 1939). It parses and builds client command lines and server
// responses; it owns no sockets, no session state machine and no MD5
// computation -- the APOP digest is an opaque 32-character hex string.
//
// Grammar (normative statement in SPEC.md):
//   command   = keyword [ SP argument ] CRLF          ; keyword case-insensitive
//   response  = status [ SP text ] CRLF [ payload "." CRLF ]
//   status    = "+OK" / "-ERR"                         ; uppercase on the wire
//   payload   = *( line CRLF )                         ; line = bytes without CR/LF
// A multiline payload line starting with "." carries one extra leading "."
// on the wire (byte-stuffing); the bare "." line is the terminator and is
// never payload. LIST/UIDL payload lines ("msg size", "msg unique-id")
// additionally populate two flat pair columns, so "lookup by message
// number" needs no per-line struct.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; Vec[StructType] is unsupported, so a response is
//     one flat record: status fields plus parallel Vecs (payload lines and
//     the LIST/UIDL pair columns), never a vector of per-line structs.
//   * Ok/Err for struct payloads are constructed only in the leaf helpers
//     _ok_request / _err_request / _ok_response / _err_response.
//   * Raw bytes widen through `(byte_at(s, i) as Int) & 0xFF`.
//   * Vec element reads are bound to typed locals before use, and every Str
//     comparison goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on a Vec[Str] element lowers to a pointer comparison).

module xiom.pop3

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// Command kind codes, carried in Pop3Request.kind and accepted by
// pop3_parse_listing for the two listing commands.
pub const POP3_USER: Int = 1;
pub const POP3_PASS: Int = 2;
pub const POP3_STAT: Int = 3;
pub const POP3_LIST: Int = 4;
pub const POP3_UIDL: Int = 5;
pub const POP3_RETR: Int = 6;
pub const POP3_DELE: Int = 7;
pub const POP3_NOOP: Int = 8;
pub const POP3_RSET: Int = 9;
pub const POP3_QUIT: Int = 10;
pub const POP3_TOP: Int = 11;
pub const POP3_APOP: Int = 12;

// Largest value accepted in any numeric argument (message number, TOP line
// count, LIST size) and in a listing column: 2^31-1. Numeric arguments are
// canonical decimal -- 1..10 ASCII digits, no leading zero (the single
// digit "0" is valid where the minimum is 0).
pub const POP3_MAX_NUM: Int = 2147483647;

// Maximum line content in bytes, excluding the CRLF, for commands,
// responses and payload lines alike. Every emitted line is therefore at
// most 512 bytes on the wire, RFC 1939's response-line limit.
pub const POP3_MAX_LINE: Int = 510;

// Maximum length in bytes of a USER or APOP name (RFC 1939 caps every
// argument at 40 characters).
pub const POP3_MAX_NAME: Int = 40;

// Unique-id length bounds in bytes (RFC 1939: 1 to 70 octets, each in
// 0x21..0x7E, so no spaces).
pub const POP3_UID_MIN: Int = 1;
pub const POP3_UID_MAX: Int = 70;

// --------------------------------------------------
//  Byte constants (Int form; UInt8 casts at push sites)
// --------------------------------------------------

const _B_CR: Int = 13;
const _B_LF: Int = 10;
const _B_SP: Int = 32;
const _B_DOT: Int = 46;
const _B_ZERO: Int = 48;
const _B_NINE: Int = 57;
const _B_UC_A: Int = 65;
const _B_UC_F: Int = 70;
const _B_UC_Z: Int = 90;
const _B_LC_A: Int = 97;
const _B_LC_F: Int = 102;
const _B_LC_Z: Int = 122;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One parsed (or to-be-built) client command.
/// Invariants by kind: USER/PASS store `text`; APOP stores `text` (name)
/// and `digest` (lowercase 32-hex); LIST/UIDL store `msg` = -1 when the
/// argument is absent; RETR/DELE store `msg`; TOP stores `msg` and `n`;
/// STAT/NOOP/RSET/QUIT store neither. `msg` and `n` are -1 when absent.
pub type Pop3Request = {
  kind: Int;
  text: Str;
  digest: Str;
  msg: Int;
  n: Int;
}

/// One parsed (or to-be-built) server response, flat by design.
/// `ok` is true for +OK, false for -ERR. `multiline` is true when the
/// response carried a payload section (status line, payload lines, "."
/// terminator), including an empty one; it is false for every -ERR and for
/// single-line +OK responses. `text` is the status-line text after the
/// single separator space ("" when absent). `lines` holds the payload lines
/// dot-unstuffed, in order. `pair_nums`/`pair_vals` are index-aligned with
/// each other and, for listing parses, with `lines`: entry i is the parsed
/// message number and value (LIST size or UIDL unique-id) of lines[i].
pub type Pop3Response = {
  ok: Bool;
  multiline: Bool;
  text: Str;
  lines: Vec[Str];
  pair_nums: Vec[Int];
  pair_vals: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(r) for Result[Pop3Request, Str].
fn _ok_request(r: Pop3Request) -> Result[Pop3Request, Str] {
  return Ok(r);
}

// Err(m) for Result[Pop3Request, Str].
fn _err_request(m: Str) -> Result[Pop3Request, Str] {
  return Err(m);
}

// Ok(r) for Result[Pop3Response, Str].
fn _ok_response(r: Pop3Response) -> Result[Pop3Response, Str] {
  return Ok(r);
}

// Err(m) for Result[Pop3Response, Str].
fn _err_response(m: Str) -> Result[Pop3Response, Str] {
  return Err(m);
}

// Ok(s) for Result[Str, Str].
fn _ok_str(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// One byte of `s` at `pos`, zero-extended to 0..255. The caller guarantees
// 0 <= pos < s.len().
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// True for an ASCII decimal digit.
fn _is_digit(b: Int) -> Bool {
  return b >= _B_ZERO && b <= _B_NINE;
}

// True for an ASCII printable byte (0x20..0x7E; DEL and 8-bit bytes are not
// printable in this codec).
fn _is_printable(b: Int) -> Bool {
  return b >= _B_SP && b <= 126;
}

// True for an ASCII hex digit (either case).
fn _is_hex(b: Int) -> Bool {
  if b >= _B_ZERO && b <= _B_NINE {
    return true;
  }
  if b >= _B_UC_A && b <= _B_UC_F {
    return true;
  }
  return b >= _B_LC_A && b <= _B_LC_F;
}

// ASCII-lowercase one hex digit; non-AF bytes pass through.
fn _lower_hex(b: Int) -> Int {
  if b >= _B_UC_A && b <= _B_UC_F {
    return b + 32;
  }
  return b;
}

// ASCII-uppercase every byte of `s` (keyword canonicalization).
fn _upper_ascii(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if b >= _B_LC_A && b <= _B_LC_Z {
      out.push((b - 32) as UInt8);
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Index of the first space in `s` at or after `from`, or -1.
fn _find_space(s: Str, from: Int) -> Int {
  let n = s.len();
  var i = from;
  while i < n {
    if _byte(s, i) == _B_SP {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first CRLF pair in `s` at or after `from`, or -1 when the
// remaining bytes do not contain one.
fn _find_crlf(s: Str, from: Int) -> Int {
  let n = s.len();
  var i = from;
  while i + 1 < n {
    if _byte(s, i) == _B_CR && _byte(s, i + 1) == _B_LF {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when every byte of `s` is printable ASCII (0x20..0x7E).
fn _all_printable(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    if !_is_printable(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `s` contains a CR or an LF byte.
fn _has_cr_or_lf(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if b == _B_CR || b == _B_LF {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Parse a canonical-decimal argument: 1..10 ASCII digits, no leading zero
// unless the value is exactly "0", value in [min, POP3_MAX_NUM].
// Returns the value, or -1 on any violation (so min must be >= 0).
fn _parse_num(s: Str, min: Int) -> Int {
  let n = s.len();
  if n == 0 || n > 10 {
    return -1;
  }
  let first = _byte(s, 0);
  if !_is_digit(first) {
    return -1;
  }
  if n > 1 && first == _B_ZERO {
    return -1;
  }
  var v = 0;
  var i = 0;
  while i < n {
    let d = _byte(s, i);
    if !_is_digit(d) {
      return -1;
    }
    v = v * 10 + (d - _B_ZERO);
    i = i + 1;
  }
  if v > POP3_MAX_NUM || v < min {
    return -1;
  }
  return v;
}

// A USER/APOP name: 1..40 printable bytes with no space.
fn _valid_name(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > POP3_MAX_NAME {
    return false;
  }
  if _find_space(s, 0) >= 0 {
    return false;
  }
  return _all_printable(s);
}

// A PASS string: 1..POP3_MAX_LINE printable bytes; spaces are part of the
// password, so embedded spaces are legal.
fn _valid_pass(s: Str) -> Bool {
  if s.len() < 1 {
    return false;
  }
  return _all_printable(s);
}

// A UIDL unique-id: 1..70 bytes, each in 0x21..0x7E.
fn _valid_uid(s: Str) -> Bool {
  let n = s.len();
  if n < POP3_UID_MIN || n > POP3_UID_MAX {
    return false;
  }
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if b < 33 || b > 126 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// An APOP digest: exactly 32 ASCII hex digits, either case.
fn _valid_digest(s: Str) -> Bool {
  if s.len() != 32 {
    return false;
  }
  var i = 0;
  while i < 32 {
    if !_is_hex(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Lowercase a hex string (canonical APOP digest form).
fn _lower_digest(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    out.push(_lower_hex(_byte(s, i)) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Request parsing
// --------------------------------------------------

/// Parse one POP3 command line (RFC 1939 command grammar).
/// Params: line - one command line, with or without its trailing CRLF; only
/// the exact two-byte CRLF is treated as a terminator (a lone CR or LF is
/// content and fails the printable-byte rule).
/// Grammar and decisions (full statement in SPEC.md):
///   * the keyword is 3 or 4 ASCII letters, matched case-insensitively and
///     stored uppercase by pop3_build_request;
///   * one space separates the keyword from its argument(s); arguments are
///     printable ASCII only, and the whole line is capped at POP3_MAX_LINE
///     bytes excluding CRLF;
///   * USER and APOP names are single tokens of 1..40 bytes with no space;
///     a PASS string is the rest of the line (embedded spaces are part of
///     the password), 1..POP3_MAX_LINE bytes;
///   * message numbers and TOP line counts are canonical decimal: 1..10
///     digits, no leading zero, value in 1..POP3_MAX_NUM (0..POP3_MAX_NUM
///     for TOP n);
///   * an APOP digest is exactly 32 hex digits, either case, stored
///     lowercased;
///   * LIST and UIDL accept an optional message number; STAT, NOOP, RSET
///     and QUIT accept no argument (a trailing space is tolerated).
/// Returns: Ok(request) for a well-formed command.
/// Error case: Err("pop3: bad argument: ...") for an empty line, an unknown
/// keyword, an unexpected or malformed argument;
/// Err("pop3: control byte in command line") for any byte outside
/// 0x20..0x7E; Err("pop3: line too long") above the cap.
/// Complexity: O(line length).
pub fn pop3_parse_request(line: Str) -> Result[Pop3Request, Str] {
  let n = line.len();
  if n == 0 {
    return _err_request("pop3: bad argument: empty command line");
  }
  var content = line;
  var clen = n;
  if n >= 2 && _byte(line, n - 2) == _B_CR && _byte(line, n - 1) == _B_LF {
    content = string.str_slice(line, 0, n - 2);
    clen = n - 2;
  }
  if clen == 0 {
    return _err_request("pop3: bad argument: empty command line");
  }
  if clen > POP3_MAX_LINE {
    return _err_request("pop3: line too long");
  }
  if !_all_printable(content) {
    return _err_request("pop3: control byte in command line");
  }
  let sp = _find_space(content, 0);
  var kw = content;
  var rest = "";
  if sp >= 0 {
    kw = string.str_slice(content, 0, sp);
    rest = string.str_slice(content, sp + 1, clen);
  }
  let upper = _upper_ascii(kw);
  var req = Pop3Request{ kind: 0; text: ""; digest: ""; msg: -1; n: -1; };
  if compare.str_compare(upper, "USER") == 0 {
    if !_valid_name(rest) {
      return _err_request("pop3: bad argument: user name");
    }
    req.kind = POP3_USER;
    req.text = rest;
  } elif compare.str_compare(upper, "PASS") == 0 {
    if !_valid_pass(rest) {
      return _err_request("pop3: bad argument: password");
    }
    req.kind = POP3_PASS;
    req.text = rest;
  } elif compare.str_compare(upper, "STAT") == 0 {
    if rest.len() > 0 {
      return _err_request("pop3: bad argument: unexpected argument");
    }
    req.kind = POP3_STAT;
  } elif compare.str_compare(upper, "LIST") == 0 {
    if rest.len() > 0 {
      let m = _parse_num(rest, 1);
      if m < 0 {
        return _err_request("pop3: bad argument: message number");
      }
      req.msg = m;
    }
    req.kind = POP3_LIST;
  } elif compare.str_compare(upper, "UIDL") == 0 {
    if rest.len() > 0 {
      let m = _parse_num(rest, 1);
      if m < 0 {
        return _err_request("pop3: bad argument: message number");
      }
      req.msg = m;
    }
    req.kind = POP3_UIDL;
  } elif compare.str_compare(upper, "RETR") == 0 {
    let m = _parse_num(rest, 1);
    if m < 0 {
      return _err_request("pop3: bad argument: message number");
    }
    req.kind = POP3_RETR;
    req.msg = m;
  } elif compare.str_compare(upper, "DELE") == 0 {
    let m = _parse_num(rest, 1);
    if m < 0 {
      return _err_request("pop3: bad argument: message number");
    }
    req.kind = POP3_DELE;
    req.msg = m;
  } elif compare.str_compare(upper, "NOOP") == 0 {
    if rest.len() > 0 {
      return _err_request("pop3: bad argument: unexpected argument");
    }
    req.kind = POP3_NOOP;
  } elif compare.str_compare(upper, "RSET") == 0 {
    if rest.len() > 0 {
      return _err_request("pop3: bad argument: unexpected argument");
    }
    req.kind = POP3_RSET;
  } elif compare.str_compare(upper, "QUIT") == 0 {
    if rest.len() > 0 {
      return _err_request("pop3: bad argument: unexpected argument");
    }
    req.kind = POP3_QUIT;
  } elif compare.str_compare(upper, "TOP") == 0 {
    let sp2 = _find_space(rest, 0);
    if sp2 <= 0 {
      return _err_request("pop3: bad argument: TOP arguments");
    }
    let ms = string.str_slice(rest, 0, sp2);
    let ns = string.str_slice(rest, sp2 + 1, rest.len());
    let m = _parse_num(ms, 1);
    let cnt = _parse_num(ns, 0);
    if m < 0 {
      return _err_request("pop3: bad argument: message number");
    }
    if cnt < 0 {
      return _err_request("pop3: bad argument: line count");
    }
    req.kind = POP3_TOP;
    req.msg = m;
    req.n = cnt;
  } elif compare.str_compare(upper, "APOP") == 0 {
    let sp2 = _find_space(rest, 0);
    if sp2 <= 0 {
      return _err_request("pop3: bad argument: apop name");
    }
    let name = string.str_slice(rest, 0, sp2);
    let dig = string.str_slice(rest, sp2 + 1, rest.len());
    if !_valid_name(name) {
      return _err_request("pop3: bad argument: apop name");
    }
    if !_valid_digest(dig) {
      return _err_request("pop3: bad argument: apop digest");
    }
    req.kind = POP3_APOP;
    req.text = name;
    req.digest = _lower_digest(dig);
  } else {
    return _err_request("pop3: bad argument: unknown command");
  }
  return _ok_request(req);
}

// --------------------------------------------------
//  Request building
// --------------------------------------------------

/// Build one canonical POP3 command line.
/// Params: req - the request; only the fields the kind uses are read, the
/// rest are ignored.
/// Returns: Ok(line) with the uppercase keyword, space-separated canonical
/// arguments and a trailing CRLF. A PASS string is emitted verbatim after
/// one space (embedded spaces included); an APOP digest is emitted
/// lowercased; numbers are emitted in canonical decimal with no leading
/// zero.
/// Error case: Err("pop3: bad argument: ...") for an unknown kind or for a
/// field that violates its kind's shape (name, password, digest, message
/// number, line count); Err("pop3: line too long") when the content exceeds
/// POP3_MAX_LINE bytes.
/// Complexity: O(argument length).
pub fn pop3_build_request(req: &Pop3Request) -> Result[Str, Str] {
  let kind: Int = req.kind;
  let text: Str = req.text;
  let digest: Str = req.digest;
  let msg: Int = req.msg;
  let n: Int = req.n;
  var out = Vec[UInt8].new();
  if kind == POP3_USER {
    if !_valid_name(text) {
      return _err_str("pop3: bad argument: user name");
    }
    builder.sb_push_str(&mut out, "USER ");
    builder.sb_push_str(&mut out, text);
  } elif kind == POP3_PASS {
    if !_valid_pass(text) {
      return _err_str("pop3: bad argument: password");
    }
    builder.sb_push_str(&mut out, "PASS ");
    builder.sb_push_str(&mut out, text);
  } elif kind == POP3_STAT {
    builder.sb_push_str(&mut out, "STAT");
  } elif kind == POP3_LIST || kind == POP3_UIDL {
    if kind == POP3_LIST {
      builder.sb_push_str(&mut out, "LIST");
    } else {
      builder.sb_push_str(&mut out, "UIDL");
    }
    if msg != -1 {
      if msg < 1 || msg > POP3_MAX_NUM {
        return _err_str("pop3: bad argument: message number");
      }
      builder.sb_push_str(&mut out, " ");
      builder.sb_push_int(&mut out, msg);
    }
  } elif kind == POP3_RETR {
    if msg < 1 || msg > POP3_MAX_NUM {
      return _err_str("pop3: bad argument: message number");
    }
    builder.sb_push_str(&mut out, "RETR ");
    builder.sb_push_int(&mut out, msg);
  } elif kind == POP3_DELE {
    if msg < 1 || msg > POP3_MAX_NUM {
      return _err_str("pop3: bad argument: message number");
    }
    builder.sb_push_str(&mut out, "DELE ");
    builder.sb_push_int(&mut out, msg);
  } elif kind == POP3_NOOP {
    builder.sb_push_str(&mut out, "NOOP");
  } elif kind == POP3_RSET {
    builder.sb_push_str(&mut out, "RSET");
  } elif kind == POP3_QUIT {
    builder.sb_push_str(&mut out, "QUIT");
  } elif kind == POP3_TOP {
    if msg < 1 || msg > POP3_MAX_NUM {
      return _err_str("pop3: bad argument: message number");
    }
    if n < 0 || n > POP3_MAX_NUM {
      return _err_str("pop3: bad argument: line count");
    }
    builder.sb_push_str(&mut out, "TOP ");
    builder.sb_push_int(&mut out, msg);
    builder.sb_push_str(&mut out, " ");
    builder.sb_push_int(&mut out, n);
  } elif kind == POP3_APOP {
    if !_valid_name(text) {
      return _err_str("pop3: bad argument: apop name");
    }
    if !_valid_digest(digest) {
      return _err_str("pop3: bad argument: apop digest");
    }
    builder.sb_push_str(&mut out, "APOP ");
    builder.sb_push_str(&mut out, text);
    builder.sb_push_str(&mut out, " ");
    builder.sb_push_str(&mut out, _lower_digest(digest));
  } else {
    return _err_str("pop3: bad argument: unknown command kind");
  }
  builder.sb_push_str(&mut out, "\r\n");
  let line = builder.sb_to_str(&out);
  if line.len() - 2 > POP3_MAX_LINE {
    return _err_str("pop3: line too long");
  }
  return _ok_str(line);
}

// --------------------------------------------------
//  Response parsing
// --------------------------------------------------

// Scan the status line of a response into `resp`.
// Returns the offset just past the terminating CRLF, or a negative code:
//   -1 no status marker     -2 missing CRLF
//   -3 control byte in text -4 line too long
fn _scan_status_line(text: Str, resp: &mut Pop3Response) -> Int {
  let n = text.len();
  if n < 3 {
    return -1;
  }
  var mlen = 0;
  if string.str_starts_with(text, "+OK") {
    mlen = 3;
    resp.ok = true;
  } elif string.str_starts_with(text, "-ERR") {
    mlen = 4;
    resp.ok = false;
  } else {
    return -1;
  }
  if n > mlen {
    let b = _byte(text, mlen);
    if b != _B_SP && b != _B_CR {
      return -1;
    }
  }
  let e = _find_crlf(text, mlen);
  if e < 0 {
    return -2;
  }
  if e > POP3_MAX_LINE {
    return -4;
  }
  if n > mlen && _byte(text, mlen) == _B_CR && e != mlen {
    return -2;
  }
  var ts = mlen;
  if n > mlen && _byte(text, mlen) == _B_SP {
    ts = mlen + 1;
  }
  var st = "";
  if e > ts {
    st = string.str_slice(text, ts, e);
    if !_all_printable(st) {
      return -3;
    }
  }
  resp.text = st;
  return e + 2;
}

// Map a _scan_status_line error code to its message.
fn _status_error(code: Int) -> Str {
  if code == -1 {
    return "pop3: bad status marker";
  }
  if code == -2 {
    return "pop3: missing CRLF";
  }
  if code == -3 {
    return "pop3: control byte in response text";
  }
  return "pop3: line too long";
}

// Parse one listing payload line ("msg value") into the pair columns of
// `resp`. Returns "" on success, the "pop3: ..." message on failure.
fn _scan_listing_line(kind: Int, line: Str, resp: &mut Pop3Response) -> Str {
  let sp = _find_space(line, 0);
  if sp <= 0 {
    return "pop3: bad argument: listing line";
  }
  let numstr = string.str_slice(line, 0, sp);
  let valstr = string.str_slice(line, sp + 1, line.len());
  let num = _parse_num(numstr, 1);
  if num < 0 {
    return "pop3: bad argument: listing message number";
  }
  if kind == POP3_LIST {
    let size = _parse_num(valstr, 0);
    if size < 0 {
      return "pop3: bad argument: listing size";
    }
  } else {
    if !_valid_uid(valstr) {
      return "pop3: bad argument: listing unique-id";
    }
  }
  resp.pair_nums.push(num);
  resp.pair_vals.push(valstr);
  return "";
}

// Scan a whole response into `resp`. Returns "" on success, the
// "pop3: ..." message on failure. `listing_kind` is 0 for a generic
// response, or POP3_LIST / POP3_UIDL to parse every payload line as a
// listing entry.
fn _scan_response(multiline: Bool, text: Str, listing_kind: Int, resp: &mut Pop3Response) -> Str {
  let after = _scan_status_line(text, resp);
  if after < 0 {
    return _status_error(after);
  }
  let total = text.len();
  if !resp.ok || !multiline {
    if after != total {
      return "pop3: text after response";
    }
    resp.multiline = false;
    return "";
  }
  resp.multiline = true;
  var p = after;
  var done = false;
  while !done {
    if p == total {
      return "pop3: unterminated multiline response";
    }
    let e = _find_crlf(text, p);
    if e < 0 {
      return "pop3: missing CRLF";
    }
    if e - p > POP3_MAX_LINE {
      return "pop3: line too long";
    }
    let line = string.str_slice(text, p, e);
    if _has_cr_or_lf(line) {
      return "pop3: control byte in payload line";
    }
    if line.len() == 1 && _byte(line, 0) == _B_DOT {
      let tail = e + 2;
      if tail != total {
        return "pop3: text after response";
      }
      done = true;
    } else {
      var payload = line;
      if line.len() > 0 && _byte(line, 0) == _B_DOT {
        payload = string.str_slice(line, 1, line.len());
      }
      if listing_kind != 0 {
        let err = _scan_listing_line(listing_kind, payload, resp);
        if err.len() > 0 {
          return err;
        }
      }
      resp.lines.push(payload);
      p = e + 2;
    }
  }
  return "";
}

/// Parse one POP3 response (RFC 1939 response grammar).
/// Params: multiline - true when the caller expects a multi-line response
/// (LIST/UIDL without an argument, RETR, TOP), false for a single-line
/// response; a -ERR response is always single-line and is accepted in
/// either mode. text - the complete response, ending with CRLF.
/// Grammar and decisions (full statement in SPEC.md):
///   * the status marker is exactly "+OK" or "-ERR" (uppercase), followed
///     by end of line or one space and printable ASCII text;
///   * every line must be CRLF-terminated; the input must be exactly one
///     response (no bytes before the marker, none after it);
///   * a multi-line payload is a sequence of CRLF-terminated lines
///     terminated by a bare "." line; each payload line starting with "."
///     is dot-unstuffed by one byte, payload lines may carry 8-bit bytes
///     but no CR or LF, and each line is capped at POP3_MAX_LINE bytes.
/// Returns: Ok(response) with the flat payload and (empty) pair columns.
/// Error case: Err("pop3: bad status marker"), Err("pop3: missing CRLF"),
/// Err("pop3: unterminated multiline response"), Err("pop3: control byte
/// in response text") / Err("pop3: control byte in payload line"),
/// Err("pop3: line too long") or Err("pop3: text after response").
/// Complexity: O(text length).
pub fn pop3_parse_response(multiline: Bool, text: Str) -> Result[Pop3Response, Str] {
  var resp = Pop3Response{
    ok: false;
    multiline: false;
    text: "";
    lines: Vec[Str].new();
    pair_nums: Vec[Int].new();
    pair_vals: Vec[Str].new();
  };
  let err = _scan_response(multiline, text, 0, &mut resp);
  if err.len() > 0 {
    return _err_response(err);
  }
  return _ok_response(resp);
}

/// Parse a LIST or UIDL response and materialize its listing pairs.
/// Params: kind - POP3_LIST for "msg size" lines (size canonical decimal,
/// 0..POP3_MAX_NUM) or POP3_UIDL for "msg unique-id" lines (1..70 bytes in
/// 0x21..0x7E); text - the complete response. The status line must be
/// followed by a payload (dot-stuffing rules as in pop3_parse_response); a
/// -ERR response parses as a single-line response with no pairs.
/// Returns: Ok(response) whose pair_nums[i]/pair_vals[i] describe
/// lines[i], so pop3_lookup_line indexes both. A "-ERR" or single-line
/// +OK response yields zero pairs.
/// Error case: Err("pop3: bad argument: kind is not LIST or UIDL") when
/// kind is neither, plus every pop3_parse_response error and
/// Err("pop3: bad argument: listing line") /
/// Err("pop3: bad argument: listing message number") /
/// Err("pop3: bad argument: listing size") /
/// Err("pop3: bad argument: listing unique-id") for a malformed entry.
/// Complexity: O(text length).
pub fn pop3_parse_listing(kind: Int, text: Str) -> Result[Pop3Response, Str] {
  if kind != POP3_LIST && kind != POP3_UIDL {
    return _err_response("pop3: bad argument: kind is not LIST or UIDL");
  }
  var resp = Pop3Response{
    ok: false;
    multiline: false;
    text: "";
    lines: Vec[Str].new();
    pair_nums: Vec[Int].new();
    pair_vals: Vec[Str].new();
  };
  let err = _scan_response(true, text, kind, &mut resp);
  if err.len() > 0 {
    return _err_response(err);
  }
  return _ok_response(resp);
}

// --------------------------------------------------
//  Response building
// --------------------------------------------------

/// Build a canonical POP3 response.
/// Params: resp - the response. `text` must be printable ASCII ("" emits a
/// bare marker); `multiline` decides whether a payload section is emitted:
/// true emits every entry of `lines` as a payload line (dot-stuffed with
/// one extra "." when it already starts with "."), then the bare "."
/// terminator, even when `lines` is empty; false emits exactly one line and
/// requires `lines` and the pair columns to be empty. A -ERR response must
/// be single-line. The pair columns are parse output and are not emitted;
/// `lines` is the single payload source.
/// Returns: Ok(text) with CRLF terminators, ready for the wire.
/// Error case: Err("pop3: control byte in response text") for a
/// non-printable status text; Err("pop3: dot-stuffing violation") for a
/// payload line containing CR or LF; Err("pop3: bad argument: ...") for a
/// -ERR response with a payload or a payload on a single-line response;
/// Err("pop3: line too long") when a line exceeds POP3_MAX_LINE bytes
/// (measured after stuffing).
/// Complexity: O(payload length).
pub fn pop3_build_response(resp: &Pop3Response) -> Result[Str, Str] {
  let ok: Bool = resp.ok;
  let multiline: Bool = resp.multiline;
  let text: Str = resp.text;
  if !_all_printable(text) {
    return _err_str("pop3: control byte in response text");
  }
  var out = Vec[UInt8].new();
  if ok {
    builder.sb_push_str(&mut out, "+OK");
  } else {
    builder.sb_push_str(&mut out, "-ERR");
  }
  if text.len() > 0 {
    builder.sb_push_str(&mut out, " ");
    builder.sb_push_str(&mut out, text);
  }
  builder.sb_push_str(&mut out, "\r\n");
  if out.len() - 2 > POP3_MAX_LINE {
    return _err_str("pop3: line too long");
  }
  let line_count = resp.lines.len();
  if !multiline {
    if line_count > 0 {
      return _err_str("pop3: bad argument: payload on a single-line response");
    }
    if resp.pair_nums.len() > 0 {
      return _err_str("pop3: bad argument: payload on a single-line response");
    }
    return _ok_str(builder.sb_to_str(&out));
  }
  if !ok {
    return _err_str("pop3: bad argument: multiline -ERR response");
  }
  var i = 0;
  while i < line_count {
    let line: Str = resp.lines[i];
    let stuffed = pop3_dot_stuff(line);
    if _has_cr_or_lf(stuffed) {
      return _err_str("pop3: dot-stuffing violation");
    }
    if stuffed.len() > POP3_MAX_LINE {
      return _err_str("pop3: line too long");
    }
    builder.sb_push_str(&mut out, stuffed);
    builder.sb_push_str(&mut out, "\r\n");
    i = i + 1;
  }
  builder.sb_push_str(&mut out, ".\r\n");
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Dot-stuffing helpers
// --------------------------------------------------

/// Byte-stuff one payload line: a line that already starts with "." gains
/// one leading "." (so a logical "." line becomes ".."); every other line
/// is returned unchanged. The empty line is unchanged.
/// Complexity: O(1) plus one allocation when stuffing applies.
pub fn pop3_dot_stuff(line: Str) -> Str {
  if line.len() > 0 && _byte(line, 0) == _B_DOT {
    return "." + line;
  }
  return line;
}

/// Remove one byte-stuffing dot: a line starting with ".." or ".<more>"
/// loses its first byte; a bare "." line is the terminator and is returned
/// unchanged (it is not payload); the empty line is unchanged.
/// Complexity: O(1) plus one allocation when stripping applies.
pub fn pop3_dot_unstuff(line: Str) -> Str {
  if line.len() > 1 && _byte(line, 0) == _B_DOT {
    return string.str_slice(line, 1, line.len());
  }
  return line;
}

// --------------------------------------------------
//  Response accessors (bounds-safe)
// --------------------------------------------------

/// True for a +OK status, false for -ERR.
pub fn pop3_is_ok(resp: &Pop3Response) -> Bool {
  return resp.ok;
}

/// True when the response carried a payload section (`+OK` under a
/// multiline expectation, including an empty payload); false for every
/// -ERR and single-line +OK.
pub fn pop3_is_multiline(resp: &Pop3Response) -> Bool {
  return resp.multiline;
}

/// The status-line text after the single separator space ("" when absent).
pub fn pop3_response_text(resp: &Pop3Response) -> Str {
  let t: Str = resp.text;
  return t;
}

/// Number of payload lines. For a listing parse this equals the pair count.
pub fn pop3_line_count(resp: &Pop3Response) -> Int {
  return resp.lines.len();
}

/// Payload line `index`, dot-unstuffed. Returns "" when index is negative
/// or >= pop3_line_count (an empty payload line is also ""); use the count
/// for bounds.
pub fn pop3_line(resp: &Pop3Response, index: Int) -> Str {
  if index < 0 || index >= resp.lines.len() {
    return "";
  }
  let line: Str = resp.lines[index];
  return line;
}

/// Number of LIST/UIDL pairs (0 for a generic parse).
pub fn pop3_pair_count(resp: &Pop3Response) -> Int {
  return resp.pair_nums.len();
}

/// Message number of pair `index`, or -1 when out of bounds.
pub fn pop3_pair_num(resp: &Pop3Response, index: Int) -> Int {
  if index < 0 || index >= resp.pair_nums.len() {
    return -1;
  }
  let v: Int = resp.pair_nums[index];
  return v;
}

/// Value of pair `index` (LIST size text or UIDL unique-id), or "" when out
/// of bounds.
pub fn pop3_pair_val(resp: &Pop3Response, index: Int) -> Str {
  if index < 0 || index >= resp.pair_vals.len() {
    return "";
  }
  let v: Str = resp.pair_vals[index];
  return v;
}

/// Index of the pair (and, for a listing parse, of the payload line) whose
/// message number is `msg`, or -1 when the message is absent. The first
/// match wins; listing order and duplicate message numbers are not
/// validated.
pub fn pop3_lookup_line(resp: &Pop3Response, msg: Int) -> Int {
  let n = resp.pair_nums.len();
  var i = 0;
  while i < n {
    let v: Int = resp.pair_nums[i];
    if v == msg {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// LIST size of message `msg`, or -1 when the message is absent or its
/// value is not canonical decimal. Only meaningful for a POP3_LIST parse.
pub fn pop3_list_size(resp: &Pop3Response, msg: Int) -> Int {
  let idx = pop3_lookup_line(resp, msg);
  if idx < 0 {
    return -1;
  }
  let v: Str = resp.pair_vals[idx];
  return _parse_num(v, 0);
}

/// UIDL unique-id of message `msg`, or "" when the message is absent. Only
/// meaningful for a POP3_UIDL parse.
pub fn pop3_uidl_id(resp: &Pop3Response, msg: Int) -> Str {
  let idx = pop3_lookup_line(resp, msg);
  if idx < 0 {
    return "";
  }
  let v: Str = resp.pair_vals[idx];
  return v;
}

/// The whole payload as one string: every payload line, dot-unstuffed in
/// parse order, terminated by CRLF ("" when there are no payload lines).
/// Complexity: O(payload length).
pub fn pop3_payload(resp: &Pop3Response) -> Str {
  var out = Vec[UInt8].new();
  let n = resp.lines.len();
  var i = 0;
  while i < n {
    let line: Str = resp.lines[i];
    builder.sb_push_str(&mut out, line);
    builder.sb_push_str(&mut out, "\r\n");
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
