// XIOM -- xiom.imap: IMAP4rev1 protocol parser (RFC 3501)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM, in-memory parser for the Internet Message Access Protocol
// version 4rev1 (RFC 3501). It parses client commands and server responses
// from a caller-owned buffer and reports how many bytes the message consumed;
// it owns no sockets, no TLS and no session state machine.
//
// Model (normative statement in SPEC.md):
//   command   = tag SP command-name [ SP arguments ] CRLF
//   response  = tagged / untagged / continuation
//   argument  = atom / quoted / literal / NIL / "(" argument *SP argument ")"
//   literal   = "{" number ["+"] "}" CRLF *OCTET   ; crosses line boundaries
//
// Parsed arguments are a flat, depth-annotated element stream: every atom,
// quoted string, literal, NIL and list marker becomes one element, so nested
// parenthesized lists need no recursion and no Vec[StructType]. A list is a
// IMAP_ARG_LIST_OPEN element, its children at depth+1, and a matching
// IMAP_ARG_LIST_CLOSE element. `consumed` counts the bytes from the parse
// start through the terminating CRLF, literals included, so the caller can
// advance a stream buffer and parse the next message.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[fn] and no
//     Vec[StructType] (parallel Vecs are pushed in the same loop so they can
//     never drift);
//   * Str values are never compared with `==` (BUG 17: `==` on a Str read
//     from a Vec[Str] element lowers to a pointer comparison); every
//     comparison routes through xiom.string.compare.str_compare;
//   * Vec[Str]/Vec[Int] element reads are bound with a typed `let` first;
//   * byte_at results are widened with `(string.byte_at(s, i) as Int) & 0xFF`;
//   * output text is accumulated in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str (never from bytes that may hold 0x00);
//   * Ok/Err for Result[ImapCommand, Str] and Result[ImapResponse, Str] are
//     constructed only in the leaf helpers below.

module xiom.imap

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// Command kind codes carried in ImapCommand.kind. UID FETCH, UID STORE and
// UID SEARCH share the kind of their base command and set ImapCommand.uid.
pub const IMAP_CMD_UNKNOWN: Int = 0;
pub const IMAP_CMD_CAPABILITY: Int = 1;
pub const IMAP_CMD_NOOP: Int = 2;
pub const IMAP_CMD_LOGOUT: Int = 3;
pub const IMAP_CMD_LOGIN: Int = 4;
pub const IMAP_CMD_SELECT: Int = 5;
pub const IMAP_CMD_EXAMINE: Int = 6;
pub const IMAP_CMD_CREATE: Int = 7;
pub const IMAP_CMD_DELETE: Int = 8;
pub const IMAP_CMD_RENAME: Int = 9;
pub const IMAP_CMD_LIST: Int = 10;
pub const IMAP_CMD_STATUS: Int = 11;
pub const IMAP_CMD_FETCH: Int = 12;
pub const IMAP_CMD_STORE: Int = 13;
pub const IMAP_CMD_SEARCH: Int = 14;
pub const IMAP_CMD_APPEND: Int = 15;
pub const IMAP_CMD_CLOSE: Int = 16;
pub const IMAP_CMD_EXPUNGE: Int = 17;

// Argument element kinds, one entry per parsed argument element.
pub const IMAP_ARG_ATOM: Int = 1;
pub const IMAP_ARG_QUOTED: Int = 2;
pub const IMAP_ARG_LITERAL: Int = 3;
pub const IMAP_ARG_LITERAL_PLUS: Int = 4;
pub const IMAP_ARG_NIL: Int = 5;
pub const IMAP_ARG_LIST_OPEN: Int = 6;
pub const IMAP_ARG_LIST_CLOSE: Int = 7;

// Response kind codes carried in ImapResponse.kind.
pub const IMAP_RESPONSE_TAGGED: Int = 1;
pub const IMAP_RESPONSE_UNTAGGED: Int = 2;
pub const IMAP_RESPONSE_CONTINUATION: Int = 3;

// Largest literal size accepted ({n} / {n+}): 2^31-1 bytes. The cap keeps the
// size inside a positive Int and documents a bound; the buffer itself is the
// real limit, because a literal that does not fit fails with its offset.
pub const IMAP_MAX_LITERAL: Int = 2147483647;

// Largest message number accepted in an untagged `* n ...` response.
pub const IMAP_MAX_NUMBER: Int = 2147483647;

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _B_CR: Int = 13;
const _B_LF: Int = 10;
const _B_SP: Int = 32;
const _B_DQUOTE: Int = 34;
const _B_PERCENT: Int = 37;
const _B_STAR: Int = 42;
const _B_PLUS: Int = 43;
const _B_LPAREN: Int = 40;
const _B_RPAREN: Int = 41;
const _B_DIGIT_0: Int = 48;
const _B_DIGIT_9: Int = 57;
const _B_BSLASH: Int = 92;
const _B_LBRACKET: Int = 91;
const _B_RBRACKET: Int = 93;
const _B_LBRACE: Int = 123;
const _B_RBRACE: Int = 125;
const _B_DEL: Int = 127;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One parsed client command.
/// `tag` is the verbatim tag; `name` the canonical uppercase command name
/// ("UID FETCH" for a UID command); `kind` one of IMAP_CMD_*; `uid` true when
/// the UID prefix was present. The element arrays describe every argument
/// element in wire order: `kinds` holds IMAP_ARG_* codes, `texts` the decoded
/// text (list markers and NIL hold "" / the literal spelling), `depths` the
/// list nesting depth (top level 0) and `offsets` each element's byte offset
/// from the start of the caller's buffer. `consumed` is the byte count from
/// the parse start through the terminating CRLF.
pub type ImapCommand = {
  tag: Str;
  name: Str;
  kind: Int;
  uid: Bool;
  consumed: Int;
  kinds: Vec[Int];
  texts: Vec[Str];
  depths: Vec[Int];
  offsets: Vec[Int];
}

/// One parsed server response.
/// `kind` is IMAP_RESPONSE_TAGGED / _UNTAGGED / _CONTINUATION. For a tagged
/// completion `tag` is the tag, `status` OK/NO/BAD and `text` the response
/// text after an optional response code. For an untagged response `status` is
/// the canonical uppercase response name (CAPABILITY, FLAGS, EXISTS, FETCH,
/// LIST, LSUB, SEARCH, STATUS, BYE, OK, ...) and `number` the message number
/// of a numbered response (-1 when absent). `code` is the uppercase
/// bracketed response code without brackets ("" when absent) and `code_args`
/// its arguments flattened to text (list parentheses dropped, quoted strings
/// unescaped). A continuation is `+` with `text` (and possibly a code).
/// The element arrays mirror ImapCommand for responses that carry arguments;
/// `consumed` is the byte count from the parse start through the final CRLF.
pub type ImapResponse = {
  kind: Int;
  tag: Str;
  status: Str;
  number: Int;
  code: Str;
  code_args: Vec[Str];
  text: Str;
  consumed: Int;
  kinds: Vec[Int];
  texts: Vec[Str];
  depths: Vec[Int];
  offsets: Vec[Int];
}

// Internal scan cursor: the buffer, the current offset, a running error and
// the last token's decoded text and kind.
type _Cur = {
  buf: Str;
  pos: Int;
  start: Int;
  err: Str;
  text: Str;
  kind: Int;
}

// Internal result of one argument scan: the four parallel element columns,
// the first error ("" on success) and the offset just past the terminating
// CRLF. The four Vecs are pushed in lockstep inside _scan_arguments.
type _Args = {
  kinds: Vec[Int];
  texts: Vec[Str];
  depths: Vec[Int];
  offsets: Vec[Int];
  err: Str;
  end: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(c) for Result[ImapCommand, Str].
fn _ok_command(c: ImapCommand) -> Result[ImapCommand, Str] {
  return Ok(c);
}

// Err(m) for Result[ImapCommand, Str].
fn _err_command(m: Str) -> Result[ImapCommand, Str] {
  return Err(m);
}

// Ok(r) for Result[ImapResponse, Str].
fn _ok_response(r: ImapResponse) -> Result[ImapResponse, Str] {
  return Ok(r);
}

// Err(m) for Result[ImapResponse, Str].
fn _err_response(m: Str) -> Result[ImapResponse, Str] {
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
  return b >= _B_DIGIT_0 && b <= _B_DIGIT_9;
}

// True for an ASCII control byte (0x00..0x1F and 0x7F).
fn _is_ctrl(b: Int) -> Bool {
  return b < _B_SP || b == _B_DEL;
}

// ASCII-uppercase every byte of `s` (keyword canonicalization).
fn _upper_ascii(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if b >= 97 && b <= 122 {
      out.push((b - 32) as UInt8);
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Bounds-safe vector helpers
// --------------------------------------------------

// Element `i` of an Int column, or -1 when out of bounds.
fn _vec_int_at(v: &Vec[Int], i: Int) -> Int {
  if i < 0 || i >= v.len() {
    return -1;
  }
  let x: Int = v[i];
  return x;
}

// Element `i` of a Str column, or "" when out of bounds.
fn _vec_str_at(v: &Vec[Str], i: Int) -> Str {
  if i < 0 || i >= v.len() {
    return "";
  }
  let x: Str = v[i];
  return x;
}

// Number of top-level arguments: depth-0 elements other than LIST_CLOSE (a
// top-level list therefore counts once, through its LIST_OPEN marker).
fn _count_top(kinds: &Vec[Int], depths: &Vec[Int]) -> Int {
  var count = 0;
  let n = kinds.len();
  var i = 0;
  while i < n {
    let k: Int = kinds[i];
    let d: Int = depths[i];
    if d == 0 && k != IMAP_ARG_LIST_CLOSE {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// Flat element index of the j-th top-level argument, or -1 when absent.
fn _top_index_of(kinds: &Vec[Int], depths: &Vec[Int], j: Int) -> Int {
  var count = 0;
  let n = kinds.len();
  var i = 0;
  while i < n {
    let k: Int = kinds[i];
    let d: Int = depths[i];
    if d == 0 && k != IMAP_ARG_LIST_CLOSE {
      if count == j {
        return i;
      }
      count = count + 1;
    }
    i = i + 1;
  }
  return -1;
}

// Kind of the j-th top-level argument, or 0 when absent.
fn _top_kind_of(kinds: &Vec[Int], depths: &Vec[Int], j: Int) -> Int {
  let i = _top_index_of(kinds, depths, j);
  if i < 0 {
    return 0;
  }
  let k: Int = kinds[i];
  return k;
}

// Text of the j-th top-level argument, or "" when absent.
fn _top_text_of(texts: &Vec[Str], kinds: &Vec[Int], depths: &Vec[Int], j: Int) -> Str {
  let i = _top_index_of(kinds, depths, j);
  if i < 0 {
    return "";
  }
  let s: Str = texts[i];
  return s;
}

// Number of direct children of the list opened at flat index `idx` (0 when
// the element is not a LIST_OPEN marker).
fn _count_children(kinds: &Vec[Int], depths: &Vec[Int], idx: Int) -> Int {
  if idx < 0 || idx >= kinds.len() {
    return 0;
  }
  let k: Int = kinds[idx];
  if k != IMAP_ARG_LIST_OPEN {
    return 0;
  }
  let d: Int = depths[idx];
  var count = 0;
  var i = idx + 1;
  let n = kinds.len();
  while i < n {
    let kk: Int = kinds[i];
    let dd: Int = depths[i];
    if dd == d + 1 && kk != IMAP_ARG_LIST_CLOSE {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// True for an element that behaves as a string: atom, quoted string or
// literal (synchronizing or not). NIL, list markers and code 0 are not.
fn _is_string_kind(k: Int) -> Bool {
  if k == IMAP_ARG_ATOM {
    return true;
  }
  if k == IMAP_ARG_QUOTED {
    return true;
  }
  if k == IMAP_ARG_LITERAL {
    return true;
  }
  return k == IMAP_ARG_LITERAL_PLUS;
}

// Individual characters that may never appear in a tag (ATOM-CHAR / SP).
fn _is_tag_special(b: Int) -> Bool {
  if b == _B_STAR || b == _B_PLUS || b == _B_PERCENT || b == _B_RBRACKET {
    return true;
  }
  if b == _B_LPAREN || b == _B_RPAREN || b == _B_LBRACE {
    return true;
  }
  return b == _B_SP;
}

// A tag: one or more printable bytes, no control byte and no tag special.
fn _valid_tag(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if _is_ctrl(b) || _is_tag_special(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// A canonical non-negative decimal number (1..10 digits, no sign) in
// 0..IMAP_MAX_NUMBER, or -1 on any violation.
fn _atom_number(s: Str) -> Int {
  let n = s.len();
  if n == 0 || n > 10 {
    return -1;
  }
  var v = 0;
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if !_is_digit(b) {
      return -1;
    }
    v = v * 10 + (b - _B_DIGIT_0);
    i = i + 1;
  }
  if v > IMAP_MAX_NUMBER {
    return -1;
  }
  return v;
}

// --------------------------------------------------
//  Cursor helpers
// --------------------------------------------------

// Set `c.err` to "imap: <what> at byte <at>".
fn _fail(c: &mut _Cur, what: Str, at: Int) {
  c.err = "imap: " + what + " at byte " + convert.int_to_string(at);
}

// One byte of the cursor buffer at `pos`, zero-extended to 0..255.
fn _cbyte(c: &mut _Cur, pos: Int) -> Int {
  return (string.byte_at(c.buf, pos) as Int) & 0xFF;
}

// Skip one or more spaces; false when the cursor is not on a space.
fn _require_space(c: &mut _Cur) -> Bool {
  let n = c.buf.len();
  var found = false;
  while c.pos < n && _cbyte(c, c.pos) == _B_SP {
    c.pos = c.pos + 1;
    found = true;
  }
  return found;
}

// Skip zero or more spaces.
fn _skip_spaces(c: &mut _Cur) {
  let n = c.buf.len();
  while c.pos < n && _cbyte(c, c.pos) == _B_SP {
    c.pos = c.pos + 1;
  }
}

// --------------------------------------------------
//  Token scanners (set c.text / c.kind; return false on error)
// --------------------------------------------------

// Scan an atom: bytes up to a space, CR, LF, "(", ")" or "{". The atom must
// not be empty, and control bytes are rejected. 8-bit bytes are opaque data.
fn _scan_atom(c: &mut _Cur) -> Bool {
  let n = c.buf.len();
  let start = c.pos;
  var sb = Vec[UInt8].new();
  var done = false;
  while !done && c.pos < n {
    let b = _cbyte(c, c.pos);
    if b == _B_SP || b == _B_CR || b == _B_LF || b == _B_LPAREN || b == _B_RPAREN || b == _B_LBRACE {
      done = true;
    } elif _is_ctrl(b) {
      _fail(c, "control byte in atom", c.pos);
      return false;
    } else {
      sb.push(b as UInt8);
      c.pos = c.pos + 1;
    }
  }
  if c.pos == start {
    _fail(c, "empty token", start);
    return false;
  }
  c.text = builder.sb_to_str(&sb);
  return true;
}

// Scan a quoted string starting at the opening DQUOTE. The only escapes are
// "\\" and "\""; any other backslash use, an unterminated string, CR, LF or
// a control byte is an error.
fn _scan_quoted(c: &mut _Cur) -> Bool {
  let start = c.pos;
  let n = c.buf.len();
  var sb = Vec[UInt8].new();
  c.pos = c.pos + 1;
  var closed = false;
  while c.pos < n {
    let b = _cbyte(c, c.pos);
    if b == _B_DQUOTE {
      closed = true;
      c.pos = c.pos + 1;
      break;
    }
    if b == _B_BSLASH {
      if c.pos + 1 >= n {
        _fail(c, "unterminated quoted string", start);
        return false;
      }
      let e = _cbyte(c, c.pos + 1);
      if e == _B_BSLASH || e == _B_DQUOTE {
        sb.push(e as UInt8);
        c.pos = c.pos + 2;
      } else {
        _fail(c, "bad quoted-string escape", c.pos);
        return false;
      }
    } elif b == _B_CR || b == _B_LF {
      _fail(c, "unterminated quoted string", start);
      return false;
    } elif _is_ctrl(b) {
      _fail(c, "control byte in quoted string", c.pos);
      return false;
    } else {
      sb.push(b as UInt8);
      c.pos = c.pos + 1;
    }
  }
  if !closed {
    _fail(c, "unterminated quoted string", start);
    return false;
  }
  c.text = builder.sb_to_str(&sb);
  return true;
}

// Scan a literal `{n}` / `{n+}` marker plus its CRLF plus the n content
// bytes. c.kind becomes IMAP_ARG_LITERAL or IMAP_ARG_LITERAL_PLUS and c.text
// the verbatim content (which may contain CR, LF and any other byte).
fn _scan_literal(c: &mut _Cur) -> Bool {
  let start = c.pos;
  let n = c.buf.len();
  c.pos = c.pos + 1;
  var value = 0;
  var digits = 0;
  var too_big = false;
  while c.pos < n && _is_digit(_cbyte(c, c.pos)) {
    let d = _cbyte(c, c.pos) - _B_DIGIT_0;
    if digits >= 10 {
      too_big = true;
    } elif value > (IMAP_MAX_LITERAL - d) / 10 {
      too_big = true;
    } else {
      value = value * 10 + d;
    }
    digits = digits + 1;
    c.pos = c.pos + 1;
  }
  if digits == 0 {
    _fail(c, "bad literal size", start);
    return false;
  }
  var plus = false;
  if c.pos < n && _cbyte(c, c.pos) == _B_PLUS {
    plus = true;
    c.pos = c.pos + 1;
  }
  if c.pos >= n || _cbyte(c, c.pos) != _B_RBRACE {
    _fail(c, "bad literal size", start);
    return false;
  }
  c.pos = c.pos + 1;
  if too_big || value > IMAP_MAX_LITERAL {
    _fail(c, "literal size exceeds the limit", start);
    return false;
  }
  if c.pos >= n || _cbyte(c, c.pos) != _B_CR || c.pos + 1 >= n || _cbyte(c, c.pos + 1) != _B_LF {
    _fail(c, "literal marker not followed by CRLF", start);
    return false;
  }
  c.pos = c.pos + 2;
  if value > n - c.pos {
    _fail(c, "literal of " + convert.int_to_string(value) + " bytes does not fit", start);
    return false;
  }
  c.text = string.str_slice(c.buf, c.pos, c.pos + value);
  if plus {
    c.kind = IMAP_ARG_LITERAL_PLUS;
  } else {
    c.kind = IMAP_ARG_LITERAL;
  }
  c.pos = c.pos + value;
  return true;
}

// Scan one argument element: quoted string, literal, atom or NIL. Sets
// c.kind (IMAP_ARG_*) and c.text; returns false with c.err set on failure.
fn _scan_one(c: &mut _Cur) -> Bool {
  let n = c.buf.len();
  if c.pos >= n {
    _fail(c, "empty token", c.pos);
    return false;
  }
  let b = _cbyte(c, c.pos);
  if b == _B_DQUOTE {
    if !_scan_quoted(c) {
      return false;
    }
    c.kind = IMAP_ARG_QUOTED;
    return true;
  }
  if b == _B_LBRACE {
    return _scan_literal(c);
  }
  if !_scan_atom(c) {
    return false;
  }
  if compare.str_compare_ignore_case(c.text, "NIL") == 0 {
    c.kind = IMAP_ARG_NIL;
  } else {
    c.kind = IMAP_ARG_ATOM;
  }
  return true;
}

// --------------------------------------------------
//  Argument-list scanning
// --------------------------------------------------

// Scan every argument element of one line, starting at `start` (the byte
// after the command name / status keyword, spaces included) and stopping at
// the terminating CRLF, which is consumed. Literals may cross line
// boundaries: their content is taken verbatim and scanning continues after
// it. Nested parentheses are tracked with a depth counter; a "(" or a token
// directly after a literal without a separating space is rejected, as are a
// stray ")", a bare CR or LF, and an unbalanced list at end of line.
fn _scan_arguments(buf: Str, start: Int) -> _Args {
  let n = buf.len();
  var kinds = Vec[Int].new();
  var texts = Vec[Str].new();
  var depths = Vec[Int].new();
  var offsets = Vec[Int].new();
  var err = "";
  var end = start;
  var c = _Cur{ buf: buf; pos: start; start: start; err: ""; text: ""; kind: 0; };
  var depth = 0;
  var done = false;
  var after_literal = false;
  while !done {
    var p = c.pos;
    var skipped = false;
    while p < n && _byte(buf, p) == _B_SP {
      p = p + 1;
      skipped = true;
    }
    if p >= n {
      err = "imap: missing CRLF at byte " + convert.int_to_string(n);
      done = true;
    } else {
      let b = _byte(buf, p);
      if b == _B_CR {
        if p + 1 >= n || _byte(buf, p + 1) != _B_LF {
          err = "imap: bare CR at byte " + convert.int_to_string(p);
          done = true;
        } elif depth > 0 {
          err = "imap: unbalanced parentheses at byte " + convert.int_to_string(p);
          done = true;
        } else {
          end = p + 2;
          done = true;
        }
      } elif b == _B_LF {
        err = "imap: bare LF at byte " + convert.int_to_string(p);
        done = true;
      } elif b == _B_RPAREN {
        if depth == 0 {
          err = "imap: unexpected closing parenthesis at byte " + convert.int_to_string(p);
          done = true;
        } else {
          depth = depth - 1;
          kinds.push(IMAP_ARG_LIST_CLOSE);
          texts.push("");
          depths.push(depth);
          offsets.push(p);
          c.pos = p + 1;
        }
      } elif b == _B_LPAREN {
        if after_literal && !skipped {
          err = "imap: literal not followed by a separator at byte " + convert.int_to_string(p);
          done = true;
        } else {
          kinds.push(IMAP_ARG_LIST_OPEN);
          texts.push("");
          depths.push(depth);
          offsets.push(p);
          depth = depth + 1;
          c.pos = p + 1;
        }
      } elif after_literal && !skipped {
        err = "imap: literal not followed by a separator at byte " + convert.int_to_string(p);
        done = true;
      } else {
        c.pos = p;
        after_literal = false;
        if !_scan_one(&mut c) {
          err = c.err;
          done = true;
        } else {
          kinds.push(c.kind);
          texts.push(c.text);
          depths.push(depth);
          offsets.push(p);
          if c.kind == IMAP_ARG_LITERAL || c.kind == IMAP_ARG_LITERAL_PLUS {
            after_literal = true;
          }
        }
      }
    }
  }
  return _Args{ kinds: kinds; texts: texts; depths: depths; offsets: offsets; err: err; end: end; };
}

// --------------------------------------------------
//  Command recognition and shape rules
// --------------------------------------------------

// Kind of a canonical uppercase command name (no UID prefix).
fn _command_kind(name: Str) -> Int {
  if compare.str_compare(name, "CAPABILITY") == 0 { return IMAP_CMD_CAPABILITY; }
  if compare.str_compare(name, "NOOP") == 0 { return IMAP_CMD_NOOP; }
  if compare.str_compare(name, "LOGOUT") == 0 { return IMAP_CMD_LOGOUT; }
  if compare.str_compare(name, "LOGIN") == 0 { return IMAP_CMD_LOGIN; }
  if compare.str_compare(name, "SELECT") == 0 { return IMAP_CMD_SELECT; }
  if compare.str_compare(name, "EXAMINE") == 0 { return IMAP_CMD_EXAMINE; }
  if compare.str_compare(name, "CREATE") == 0 { return IMAP_CMD_CREATE; }
  if compare.str_compare(name, "DELETE") == 0 { return IMAP_CMD_DELETE; }
  if compare.str_compare(name, "RENAME") == 0 { return IMAP_CMD_RENAME; }
  if compare.str_compare(name, "LIST") == 0 { return IMAP_CMD_LIST; }
  if compare.str_compare(name, "STATUS") == 0 { return IMAP_CMD_STATUS; }
  if compare.str_compare(name, "FETCH") == 0 { return IMAP_CMD_FETCH; }
  if compare.str_compare(name, "STORE") == 0 { return IMAP_CMD_STORE; }
  if compare.str_compare(name, "SEARCH") == 0 { return IMAP_CMD_SEARCH; }
  if compare.str_compare(name, "APPEND") == 0 { return IMAP_CMD_APPEND; }
  if compare.str_compare(name, "CLOSE") == 0 { return IMAP_CMD_CLOSE; }
  if compare.str_compare(name, "EXPUNGE") == 0 { return IMAP_CMD_EXPUNGE; }
  return IMAP_CMD_UNKNOWN;
}

// Kind of a canonical uppercase sub-command allowed after "UID".
fn _uid_subcommand_kind(name: Str) -> Int {
  if compare.str_compare(name, "FETCH") == 0 { return IMAP_CMD_FETCH; }
  if compare.str_compare(name, "STORE") == 0 { return IMAP_CMD_STORE; }
  if compare.str_compare(name, "SEARCH") == 0 { return IMAP_CMD_SEARCH; }
  return IMAP_CMD_UNKNOWN;
}

// Display name of a command kind for error messages.
fn _cmd_label(kind: Int) -> Str {
  if kind == IMAP_CMD_CAPABILITY { return "CAPABILITY"; }
  if kind == IMAP_CMD_NOOP { return "NOOP"; }
  if kind == IMAP_CMD_LOGOUT { return "LOGOUT"; }
  if kind == IMAP_CMD_LOGIN { return "LOGIN"; }
  if kind == IMAP_CMD_SELECT { return "SELECT"; }
  if kind == IMAP_CMD_EXAMINE { return "EXAMINE"; }
  if kind == IMAP_CMD_CREATE { return "CREATE"; }
  if kind == IMAP_CMD_DELETE { return "DELETE"; }
  if kind == IMAP_CMD_RENAME { return "RENAME"; }
  if kind == IMAP_CMD_LIST { return "LIST"; }
  if kind == IMAP_CMD_STATUS { return "STATUS"; }
  if kind == IMAP_CMD_FETCH { return "FETCH"; }
  if kind == IMAP_CMD_STORE { return "STORE"; }
  if kind == IMAP_CMD_SEARCH { return "SEARCH"; }
  if kind == IMAP_CMD_APPEND { return "APPEND"; }
  if kind == IMAP_CMD_CLOSE { return "CLOSE"; }
  if kind == IMAP_CMD_EXPUNGE { return "EXPUNGE"; }
  return "command";
}

// Validate the top-level argument shape of one command. Returns "" on
// success or a "bad command shape: ..." fragment (the caller appends the
// offset). Only structure is checked: mailbox strings, sequence sets, flags
// and search keys are opaque text.
fn _check_command_shape(kind: Int, uid: Bool, a: &_Args) -> Str {
  let kinds: Vec[Int] = a.kinds;
  let depths: Vec[Int] = a.depths;
  let texts: Vec[Str] = a.texts;
  let cnt = _count_top(&kinds, &depths);
  var label = _cmd_label(kind);
  if uid {
    label = "UID " + label;
  }
  if kind == IMAP_CMD_CAPABILITY || kind == IMAP_CMD_NOOP || kind == IMAP_CMD_LOGOUT || kind == IMAP_CMD_CLOSE || kind == IMAP_CMD_EXPUNGE {
    if cnt != 0 {
      return "bad command shape: " + label + " takes no arguments";
    }
    return "";
  }
  if kind == IMAP_CMD_LOGIN {
    if cnt != 2 {
      return "bad command shape: " + label + " expects two arguments";
    }
    if !_is_string_kind(_top_kind_of(&kinds, &depths, 0)) || !_is_string_kind(_top_kind_of(&kinds, &depths, 1)) {
      return "bad command shape: " + label + " arguments must be strings";
    }
    return "";
  }
  if kind == IMAP_CMD_SELECT || kind == IMAP_CMD_EXAMINE || kind == IMAP_CMD_CREATE || kind == IMAP_CMD_DELETE {
    if cnt != 1 {
      return "bad command shape: " + label + " expects one mailbox argument";
    }
    if !_is_string_kind(_top_kind_of(&kinds, &depths, 0)) {
      return "bad command shape: " + label + " mailbox must be a string";
    }
    return "";
  }
  if kind == IMAP_CMD_RENAME {
    if cnt != 2 {
      return "bad command shape: " + label + " expects two mailbox arguments";
    }
    if !_is_string_kind(_top_kind_of(&kinds, &depths, 0)) || !_is_string_kind(_top_kind_of(&kinds, &depths, 1)) {
      return "bad command shape: " + label + " mailboxes must be strings";
    }
    return "";
  }
  if kind == IMAP_CMD_LIST {
    if cnt != 2 {
      return "bad command shape: " + label + " expects a reference and a mailbox pattern";
    }
    let k0 = _top_kind_of(&kinds, &depths, 0);
    if !_is_string_kind(k0) && k0 != IMAP_ARG_NIL {
      return "bad command shape: " + label + " reference must be a string or NIL";
    }
    if !_is_string_kind(_top_kind_of(&kinds, &depths, 1)) {
      return "bad command shape: " + label + " pattern must be a string";
    }
    return "";
  }
  if kind == IMAP_CMD_STATUS {
    if cnt != 2 {
      return "bad command shape: " + label + " expects a mailbox and an item list";
    }
    if !_is_string_kind(_top_kind_of(&kinds, &depths, 0)) {
      return "bad command shape: " + label + " mailbox must be a string";
    }
    let idx = _top_index_of(&kinds, &depths, 1);
    if idx < 0 {
      return "bad command shape: " + label + " expects a parenthesized item list";
    }
    let k1: Int = kinds[idx];
    if k1 != IMAP_ARG_LIST_OPEN {
      return "bad command shape: " + label + " expects a parenthesized item list";
    }
    if _count_children(&kinds, &depths, idx) < 1 {
      return "bad command shape: " + label + " item list is empty";
    }
    return "";
  }
  if kind == IMAP_CMD_FETCH {
    if cnt != 2 {
      return "bad command shape: " + label + " expects a sequence set and an attribute list";
    }
    if !_is_string_kind(_top_kind_of(&kinds, &depths, 0)) {
      return "bad command shape: " + label + " sequence set must be a string";
    }
    let k1 = _top_kind_of(&kinds, &depths, 1);
    if k1 == IMAP_ARG_LIST_OPEN {
      let idx = _top_index_of(&kinds, &depths, 1);
      if _count_children(&kinds, &depths, idx) < 1 {
        return "bad command shape: " + label + " attribute list is empty";
      }
      return "";
    }
    if _is_string_kind(k1) {
      return "";
    }
    return "bad command shape: " + label + " expects an attribute or a parenthesized list";
  }
  if kind == IMAP_CMD_STORE {
    if cnt < 2 || cnt > 3 {
      return "bad command shape: " + label + " expects a sequence set, an item name and an optional flag list";
    }
    if !_is_string_kind(_top_kind_of(&kinds, &depths, 0)) {
      return "bad command shape: " + label + " sequence set must be a string";
    }
    if _top_kind_of(&kinds, &depths, 1) != IMAP_ARG_ATOM {
      return "bad command shape: " + label + " item name must be an atom";
    }
    let item = _upper_ascii(_top_text_of(&texts, &kinds, &depths, 1));
    if compare.str_compare(item, "FLAGS") != 0 && compare.str_compare(item, "+FLAGS") != 0 && compare.str_compare(item, "-FLAGS") != 0 {
      return "bad command shape: " + label + " item name must be FLAGS, +FLAGS or -FLAGS";
    }
    if cnt == 3 {
      let k2 = _top_kind_of(&kinds, &depths, 2);
      if k2 != IMAP_ARG_LIST_OPEN && !_is_string_kind(k2) {
        return "bad command shape: " + label + " expects a flag list";
      }
    }
    return "";
  }
  if kind == IMAP_CMD_SEARCH {
    if cnt < 1 {
      return "bad command shape: " + label + " expects at least one criterion";
    }
    return "";
  }
  if kind == IMAP_CMD_APPEND {
    if cnt < 2 || cnt > 4 {
      return "bad command shape: " + label + " expects a mailbox, optional flags/date and a message literal";
    }
    if !_is_string_kind(_top_kind_of(&kinds, &depths, 0)) {
      return "bad command shape: " + label + " mailbox must be a string";
    }
    let kl = _top_kind_of(&kinds, &depths, cnt - 1);
    if kl != IMAP_ARG_LITERAL && kl != IMAP_ARG_LITERAL_PLUS {
      return "bad command shape: " + label + " message must be a literal";
    }
    if cnt == 4 {
      if _top_kind_of(&kinds, &depths, 1) != IMAP_ARG_LIST_OPEN {
        return "bad command shape: " + label + " flag list must be parenthesized";
      }
      if _top_kind_of(&kinds, &depths, 2) != IMAP_ARG_QUOTED {
        return "bad command shape: " + label + " date-time must be a quoted string";
      }
    } elif cnt == 3 {
      let k1 = _top_kind_of(&kinds, &depths, 1);
      if k1 != IMAP_ARG_LIST_OPEN && k1 != IMAP_ARG_QUOTED {
        return "bad command shape: " + label + " expects a parenthesized flag list or a quoted date-time";
      }
    }
    return "";
  }
  return "";
}

// --------------------------------------------------
//  Command parsing
// --------------------------------------------------

/// Parse one command starting at byte offset `pos` of `buf`.
/// Params: buf - a caller-owned buffer that may hold one command followed by
/// more data (the parse stops at the command's own terminating CRLF);
/// pos - the offset of the tag, usually 0.
/// Returns: Ok(command) whose `consumed` counts the bytes from `pos` through
/// the terminating CRLF (literal bytes included, so multi-line commands are
/// measured correctly) and `offsets` each element's absolute byte offset.
/// Error case: Err("imap: ...") for a malformed tag, missing or unknown
/// command name, an argument-bearing malformed token, a bad quoted string,
/// a bad literal size / missing CRLF after a literal / a literal that does
/// not fit, a bare CR or LF, unbalanced parentheses, a stray ")", or a
/// command whose argument shape violates the table in SPEC.md; most messages
/// end with "at byte N".
/// Complexity: O(bytes consumed).
pub fn imap_parse_command_at(buf: Str, pos: Int) -> Result[ImapCommand, Str] {
  let n = buf.len();
  if pos < 0 || pos > n {
    return _err_command("imap: bad start offset");
  }
  if pos == n {
    return _err_command("imap: missing CRLF at byte " + convert.int_to_string(n));
  }
  var c = _Cur{ buf: buf; pos: pos; start: pos; err: ""; text: ""; kind: 0; };
  if !_scan_atom(&mut c) {
    return _err_command(c.err);
  }
  let tag: Str = c.text;
  if !_valid_tag(tag) {
    _fail(&mut c, "bad tag", pos);
    return _err_command(c.err);
  }
  let tag_end = c.pos;
  if !_require_space(&mut c) {
    _fail(&mut c, "missing command name", c.pos);
    return _err_command(c.err);
  }
  if !_scan_atom(&mut c) {
    return _err_command(c.err);
  }
  let w1: Str = c.text;
  let w1_at = c.pos - w1.len();
  let name1: Str = _upper_ascii(w1);
  var uid = false;
  var name: Str = name1;
  var kind = _command_kind(name1);
  if compare.str_compare(name1, "UID") == 0 {
    if !_require_space(&mut c) {
      _fail(&mut c, "bad UID command", w1_at);
      return _err_command(c.err);
    }
    if !_scan_atom(&mut c) {
      return _err_command(c.err);
    }
    let w2: Str = _upper_ascii(c.text);
    kind = _uid_subcommand_kind(w2);
    if kind == IMAP_CMD_UNKNOWN {
      _fail(&mut c, "unknown command", w1_at);
      return _err_command(c.err);
    }
    uid = true;
    name = "UID " + w2;
  } elif kind == IMAP_CMD_UNKNOWN {
    _fail(&mut c, "unknown command", w1_at);
    return _err_command(c.err);
  }
  let a: _Args = _scan_arguments(buf, c.pos);
  if a.err.len() > 0 {
    return _err_command(a.err);
  }
  let frag = _check_command_shape(kind, uid, &a);
  if frag.len() > 0 {
    return _err_command("imap: " + frag + " at byte " + convert.int_to_string(tag_end));
  }
  var cmd = ImapCommand{
    tag: tag;
    name: name;
    kind: kind;
    uid: uid;
    consumed: a.end - pos;
    kinds: a.kinds;
    texts: a.texts;
    depths: a.depths;
    offsets: a.offsets;
  };
  return _ok_command(cmd);
}

/// Parse one command from the start of `buf` (see imap_parse_command_at).
pub fn imap_parse_command(buf: Str) -> Result[ImapCommand, Str] {
  return imap_parse_command_at(buf, 0);
}

// --------------------------------------------------
//  Response element scanning
// --------------------------------------------------

// Status keywords that carry human text (and an optional response code)
// instead of argument elements.
fn _status_is_text(s: Str) -> Bool {
  if compare.str_compare(s, "OK") == 0 { return true; }
  if compare.str_compare(s, "NO") == 0 { return true; }
  if compare.str_compare(s, "BAD") == 0 { return true; }
  if compare.str_compare(s, "BYE") == 0 { return true; }
  return compare.str_compare(s, "PREAUTH") == 0;
}

// Status keywords that must be preceded by a message number.
fn _status_needs_number(s: Str) -> Bool {
  if compare.str_compare(s, "EXISTS") == 0 { return true; }
  if compare.str_compare(s, "RECENT") == 0 { return true; }
  if compare.str_compare(s, "EXPUNGE") == 0 { return true; }
  return compare.str_compare(s, "FETCH") == 0;
}

// Scan a bracketed response code "[CODE args]" into resp.code and
// resp.code_args (arguments flattened: list markers dropped, quoted strings
// unescaped). The cursor sits on "[" and ends just past "]". The code word
// is uppercased; its arguments stay verbatim.
fn _scan_code(c: &mut _Cur, resp: &mut ImapResponse) -> Bool {
  let start = c.pos;
  let n = c.buf.len();
  var p = start + 1;
  var in_quote = false;
  var closed = false;
  var close_at = -1;
  while p < n {
    let b = _byte(c.buf, p);
    if in_quote {
      if b == _B_BSLASH {
        p = p + 2;
      } elif b == _B_DQUOTE {
        in_quote = false;
        p = p + 1;
      } else {
        p = p + 1;
      }
    } else {
      if b == _B_DQUOTE {
        in_quote = true;
        p = p + 1;
      } elif b == _B_RBRACKET {
        closed = true;
        close_at = p;
        break;
      } elif b == _B_CR || b == _B_LF {
        break;
      } else {
        p = p + 1;
      }
    }
  }
  if !closed {
    _fail(c, "unterminated response code", start);
    return false;
  }
  let content = string.str_slice(c.buf, start + 1, close_at);
  c.pos = close_at + 1;
  let a: _Args = _scan_arguments(content + "\r\n", 0);
  if a.err.len() > 0 {
    _fail(c, "bad response code", start);
    return false;
  }
  if a.kinds.len() == 0 {
    _fail(c, "bad response code", start);
    return false;
  }
  let k0: Int = a.kinds[0];
  if k0 != IMAP_ARG_ATOM {
    _fail(c, "bad response code", start);
    return false;
  }
  let t0: Str = a.texts[0];
  resp.code = _upper_ascii(t0);
  var i = 1;
  while i < a.kinds.len() {
    let kk: Int = a.kinds[i];
    if kk != IMAP_ARG_LIST_OPEN && kk != IMAP_ARG_LIST_CLOSE {
      let tt: Str = a.texts[i];
      resp.code_args.push(tt);
    }
    i = i + 1;
  }
  return true;
}

// Parse the tail of a text-bearing response: an optional "[CODE args]"
// response code, then the response text up to the terminating CRLF, which is
// consumed. The text is verbatim bytes ("" when absent).
fn _parse_text_tail(c: &mut _Cur, resp: &mut ImapResponse) -> Bool {
  _skip_spaces(c);
  let n = c.buf.len();
  if c.pos >= n {
    _fail(c, "missing CRLF", n);
    return false;
  }
  let b = _cbyte(c, c.pos);
  if b == _B_CR {
    if c.pos + 1 >= n || _cbyte(c, c.pos + 1) != _B_LF {
      _fail(c, "bare CR", c.pos);
      return false;
    }
    c.pos = c.pos + 2;
    resp.text = "";
    return true;
  }
  if b == _B_LBRACKET {
    if !_scan_code(c, resp) {
      return false;
    }
    _skip_spaces(c);
  }
  let start = c.pos;
  var p = start;
  while p < n && _byte(c.buf, p) != _B_CR && _byte(c.buf, p) != _B_LF {
    p = p + 1;
  }
  if p >= n {
    _fail(c, "missing CRLF", n);
    return false;
  }
  if _byte(c.buf, p) == _B_LF {
    _fail(c, "bare LF", p);
    return false;
  }
  if p + 1 >= n || _byte(c.buf, p + 1) != _B_LF {
    _fail(c, "bare CR", p);
    return false;
  }
  resp.text = string.str_slice(c.buf, start, p);
  c.pos = p + 2;
  return true;
}

// Validate the argument shape of an untagged response whose status already
// sits in resp.status, against the RFC 3501 forms for STATUS, LIST/LSUB,
// FLAGS, EXISTS, RECENT, EXPUNGE and FETCH. CAPABILITY, SEARCH and unknown
// (extension) statuses are accepted generically.
fn _check_untagged_shape(c: &mut _Cur, resp: &mut ImapResponse) -> Bool {
  let kinds: Vec[Int] = resp.kinds;
  let depths: Vec[Int] = resp.depths;
  let cnt = _count_top(&kinds, &depths);
  let st: Str = resp.status;
  if compare.str_compare(st, "STATUS") == 0 {
    if cnt != 2 {
      _fail(c, "bad STATUS response", c.start);
      return false;
    }
    if !_is_string_kind(_top_kind_of(&kinds, &depths, 0)) {
      _fail(c, "bad STATUS response", c.start);
      return false;
    }
    let idx = _top_index_of(&kinds, &depths, 1);
    if idx < 0 {
      _fail(c, "bad STATUS response", c.start);
      return false;
    }
    let k1: Int = kinds[idx];
    if k1 != IMAP_ARG_LIST_OPEN {
      _fail(c, "bad STATUS response", c.start);
      return false;
    }
    let cc = _count_children(&kinds, &depths, idx);
    if cc < 2 || cc % 2 != 0 {
      _fail(c, "bad STATUS response", c.start);
      return false;
    }
    return true;
  }
  if compare.str_compare(st, "LIST") == 0 || compare.str_compare(st, "LSUB") == 0 {
    if cnt != 3 {
      _fail(c, "bad mailbox list response", c.start);
      return false;
    }
    if _top_kind_of(&kinds, &depths, 0) != IMAP_ARG_LIST_OPEN {
      _fail(c, "bad mailbox list response", c.start);
      return false;
    }
    let k1 = _top_kind_of(&kinds, &depths, 1);
    if !_is_string_kind(k1) && k1 != IMAP_ARG_NIL {
      _fail(c, "bad mailbox list response", c.start);
      return false;
    }
    if !_is_string_kind(_top_kind_of(&kinds, &depths, 2)) {
      _fail(c, "bad mailbox list response", c.start);
      return false;
    }
    return true;
  }
  if compare.str_compare(st, "FLAGS") == 0 {
    if cnt != 1 {
      _fail(c, "bad FLAGS response", c.start);
      return false;
    }
    if _top_kind_of(&kinds, &depths, 0) != IMAP_ARG_LIST_OPEN {
      _fail(c, "bad FLAGS response", c.start);
      return false;
    }
    return true;
  }
  if compare.str_compare(st, "EXISTS") == 0 || compare.str_compare(st, "RECENT") == 0 || compare.str_compare(st, "EXPUNGE") == 0 {
    if cnt != 0 {
      _fail(c, "bad numbered response", c.start);
      return false;
    }
    return true;
  }
  if compare.str_compare(st, "FETCH") == 0 {
    if cnt < 1 {
      _fail(c, "bad FETCH response", c.start);
      return false;
    }
    if _top_kind_of(&kinds, &depths, 0) != IMAP_ARG_LIST_OPEN {
      _fail(c, "bad FETCH response", c.start);
      return false;
    }
    return true;
  }
  return true;
}

// Parse one untagged response. The cursor sits on "*".
fn _parse_untagged(c: &mut _Cur, resp: &mut ImapResponse) -> Bool {
  resp.kind = IMAP_RESPONSE_UNTAGGED;
  c.pos = c.pos + 1;
  if !_require_space(c) {
    _fail(c, "bad untagged response", c.pos);
    return false;
  }
  _skip_spaces(c);
  let n = c.buf.len();
  if c.pos >= n {
    _fail(c, "missing CRLF", n);
    return false;
  }
  if !_scan_atom(c) {
    return false;
  }
  let first: Str = c.text;
  var numbered = false;
  if _is_digit(_byte(first, 0)) {
    let num = _atom_number(first);
    if num < 0 {
      _fail(c, "bad message number", c.pos - first.len());
      return false;
    }
    resp.number = num;
    numbered = true;
    if !_require_space(c) {
      _fail(c, "bad untagged response", c.pos);
      return false;
    }
    if !_scan_atom(c) {
      return false;
    }
    resp.status = _upper_ascii(c.text);
  } else {
    resp.status = _upper_ascii(first);
  }
  if _status_is_text(resp.status) {
    if numbered {
      _fail(c, "unexpected message number", c.pos);
      return false;
    }
    return _parse_text_tail(c, resp);
  }
  if numbered && !_status_needs_number(resp.status) {
    _fail(c, "unexpected message number", c.pos);
    return false;
  }
  if !numbered && _status_needs_number(resp.status) {
    _fail(c, "message number required", c.pos);
    return false;
  }
  let a: _Args = _scan_arguments(c.buf, c.pos);
  if a.err.len() > 0 {
    c.err = a.err;
    return false;
  }
  c.pos = a.end;
  resp.kinds = a.kinds;
  resp.texts = a.texts;
  resp.depths = a.depths;
  resp.offsets = a.offsets;
  return _check_untagged_shape(c, resp);
}

// Parse one tagged completion. The cursor sits on the first tag byte.
fn _parse_tagged(c: &mut _Cur, resp: &mut ImapResponse) -> Bool {
  resp.kind = IMAP_RESPONSE_TAGGED;
  let start = c.pos;
  if !_scan_atom(c) {
    return false;
  }
  let tag: Str = c.text;
  if !_valid_tag(tag) {
    _fail(c, "bad tag", start);
    return false;
  }
  resp.tag = tag;
  if !_require_space(c) {
    _fail(c, "bad tagged response", c.pos);
    return false;
  }
  if !_scan_atom(c) {
    return false;
  }
  let st: Str = _upper_ascii(c.text);
  resp.status = st;
  if compare.str_compare(st, "OK") != 0 && compare.str_compare(st, "NO") != 0 && compare.str_compare(st, "BAD") != 0 {
    _fail(c, "bad tagged response status", start);
    return false;
  }
  return _parse_text_tail(c, resp);
}

// Parse one continuation request. The cursor sits on "+".
fn _parse_continuation(c: &mut _Cur, resp: &mut ImapResponse) -> Bool {
  resp.kind = IMAP_RESPONSE_CONTINUATION;
  c.pos = c.pos + 1;
  let n = c.buf.len();
  if c.pos >= n {
    _fail(c, "missing CRLF", n);
    return false;
  }
  let b = _cbyte(c, c.pos);
  if b != _B_SP && b != _B_CR {
    _fail(c, "bad continuation response", c.pos);
    return false;
  }
  return _parse_text_tail(c, resp);
}

// --------------------------------------------------
//  Response parsing
// --------------------------------------------------

/// Parse one response starting at byte offset `pos` of `buf`.
/// Params: buf - a caller-owned buffer that may hold one response followed by
/// more data; pos - the offset of "*", "+" or the tag.
/// Returns: Ok(response) covering exactly one response; `consumed` counts
/// the bytes from `pos` through the final CRLF, so literals inside FETCH
/// responses (which cross line boundaries) extend it. A tagged completion is
/// `tag SP OK/NO/BAD [code] text CRLF`; an untagged response is
/// `* SP keyword [arguments] CRLF`, optionally numbered (`* n EXISTS`,
/// `FETCH`, `RECENT`, `EXPUNGE`); a continuation is `+ [SP [code] text] CRLF`.
/// The bracketed response code (e.g. READ-ONLY, TRYCREATE, ALERT, UIDVALIDITY
/// 123) is exposed uppercased in `code` with its arguments flattened into
/// `code_args`.
/// Error case: Err("imap: ...") for a non-CRLF line end, a bare CR or LF, an
/// unknown tag or a tag special, a bad or unexpected status keyword, a
/// wrong number/status combination, a malformed argument token, unbalanced
/// parentheses, an unterminated or malformed response code, and every
/// lexical error imap_parse_command_at reports; most messages end with
/// "at byte N".
/// Complexity: O(bytes consumed).
pub fn imap_parse_response_at(buf: Str, pos: Int) -> Result[ImapResponse, Str] {
  let n = buf.len();
  if pos < 0 || pos > n {
    return _err_response("imap: bad start offset");
  }
  if pos == n {
    return _err_response("imap: missing CRLF at byte " + convert.int_to_string(n));
  }
  var c = _Cur{ buf: buf; pos: pos; start: pos; err: ""; text: ""; kind: 0; };
  var resp = ImapResponse{
    kind: 0;
    tag: "";
    status: "";
    number: -1;
    code: "";
    code_args: Vec[Str].new();
    text: "";
    consumed: 0;
    kinds: Vec[Int].new();
    texts: Vec[Str].new();
    depths: Vec[Int].new();
    offsets: Vec[Int].new();
  };
  let b = _byte(buf, pos);
  var ok = false;
  if b == _B_STAR {
    ok = _parse_untagged(&mut c, &mut resp);
  } elif b == _B_PLUS {
    ok = _parse_continuation(&mut c, &mut resp);
  } else {
    ok = _parse_tagged(&mut c, &mut resp);
  }
  if !ok {
    return _err_response(c.err);
  }
  resp.consumed = c.pos - pos;
  return _ok_response(resp);
}

/// Parse one response from the start of `buf` (see imap_parse_response_at).
pub fn imap_parse_response(buf: Str) -> Result[ImapResponse, Str] {
  return imap_parse_response_at(buf, 0);
}

// --------------------------------------------------
//  Command accessors (bounds-safe, sentinel-based)
// --------------------------------------------------

/// The command tag, verbatim.
pub fn imap_command_tag(cmd: &ImapCommand) -> Str {
  let s: Str = cmd.tag;
  return s;
}

/// The canonical uppercase command name ("UID FETCH" for UID commands).
pub fn imap_command_name(cmd: &ImapCommand) -> Str {
  let s: Str = cmd.name;
  return s;
}

/// The command kind (IMAP_CMD_*).
pub fn imap_command_kind(cmd: &ImapCommand) -> Int {
  let k: Int = cmd.kind;
  return k;
}

/// True when the command carried the UID prefix.
pub fn imap_command_is_uid(cmd: &ImapCommand) -> Bool {
  let v: Bool = cmd.uid;
  return v;
}

/// Bytes consumed from the parse start through the terminating CRLF.
pub fn imap_command_consumed(cmd: &ImapCommand) -> Int {
  let v: Int = cmd.consumed;
  return v;
}

/// Number of top-level arguments (a top-level list counts once).
pub fn imap_command_arg_count(cmd: &ImapCommand) -> Int {
  let k: Vec[Int] = cmd.kinds;
  let d: Vec[Int] = cmd.depths;
  return _count_top(&k, &d);
}

/// Kind of top-level argument `index` (IMAP_ARG_*), or 0 when absent.
pub fn imap_command_arg_kind(cmd: &ImapCommand, index: Int) -> Int {
  let k: Vec[Int] = cmd.kinds;
  let d: Vec[Int] = cmd.depths;
  return _top_kind_of(&k, &d, index);
}

/// Decoded text of top-level argument `index` ("" for list markers and NIL);
/// "" when the index is out of range.
pub fn imap_command_arg_text(cmd: &ImapCommand, index: Int) -> Str {
  let k: Vec[Int] = cmd.kinds;
  let d: Vec[Int] = cmd.depths;
  let t: Vec[Str] = cmd.texts;
  return _top_text_of(&t, &k, &d, index);
}

/// Number of flat argument elements (list markers included).
pub fn imap_command_element_count(cmd: &ImapCommand) -> Int {
  let v: Vec[Int] = cmd.kinds;
  return v.len();
}

/// Kind of element `index` (IMAP_ARG_*), or -1 when out of range.
pub fn imap_command_element_kind(cmd: &ImapCommand, index: Int) -> Int {
  let v: Vec[Int] = cmd.kinds;
  return _vec_int_at(&v, index);
}

/// Decoded text of element `index`, or "" when out of range.
pub fn imap_command_element_text(cmd: &ImapCommand, index: Int) -> Str {
  let v: Vec[Str] = cmd.texts;
  return _vec_str_at(&v, index);
}

/// List nesting depth of element `index` (top level 0), or -1 when out of
/// range.
pub fn imap_command_element_depth(cmd: &ImapCommand, index: Int) -> Int {
  let v: Vec[Int] = cmd.depths;
  return _vec_int_at(&v, index);
}

/// Absolute byte offset of element `index` in the caller's buffer, or -1
/// when out of range.
pub fn imap_command_element_offset(cmd: &ImapCommand, index: Int) -> Int {
  let v: Vec[Int] = cmd.offsets;
  return _vec_int_at(&v, index);
}

// --------------------------------------------------
//  Response accessors (bounds-safe, sentinel-based)
// --------------------------------------------------

/// The response kind (IMAP_RESPONSE_*).
pub fn imap_response_kind(resp: &ImapResponse) -> Int {
  let v: Int = resp.kind;
  return v;
}

/// The tag of a tagged completion, "" otherwise.
pub fn imap_response_tag(resp: &ImapResponse) -> Str {
  let s: Str = resp.tag;
  return s;
}

/// Canonical uppercase status keyword ("" for continuations).
pub fn imap_response_status(resp: &ImapResponse) -> Str {
  let s: Str = resp.status;
  return s;
}

/// Message number of a numbered untagged response, -1 when absent.
pub fn imap_response_number(resp: &ImapResponse) -> Int {
  let v: Int = resp.number;
  return v;
}

/// Bracketed response code without brackets, uppercased, "" when absent.
pub fn imap_response_code(resp: &ImapResponse) -> Str {
  let s: Str = resp.code;
  return s;
}

/// Number of response-code arguments.
pub fn imap_response_code_arg_count(resp: &ImapResponse) -> Int {
  let v: Vec[Str] = resp.code_args;
  return v.len();
}

/// Response-code argument `index`, or "" when out of range.
pub fn imap_response_code_arg(resp: &ImapResponse, index: Int) -> Str {
  let v: Vec[Str] = resp.code_args;
  return _vec_str_at(&v, index);
}

/// Response text: the text after status (and code) for text-bearing
/// responses, "" otherwise.
pub fn imap_response_text(resp: &ImapResponse) -> Str {
  let s: Str = resp.text;
  return s;
}

/// Bytes consumed from the parse start through the final CRLF.
pub fn imap_response_consumed(resp: &ImapResponse) -> Int {
  let v: Int = resp.consumed;
  return v;
}

/// Number of top-level arguments of an argument-bearing response.
pub fn imap_response_arg_count(resp: &ImapResponse) -> Int {
  let k: Vec[Int] = resp.kinds;
  let d: Vec[Int] = resp.depths;
  return _count_top(&k, &d);
}

/// Kind of top-level argument `index` (IMAP_ARG_*), or 0 when absent.
pub fn imap_response_arg_kind(resp: &ImapResponse, index: Int) -> Int {
  let k: Vec[Int] = resp.kinds;
  let d: Vec[Int] = resp.depths;
  return _top_kind_of(&k, &d, index);
}

/// Decoded text of top-level argument `index`, "" when absent.
pub fn imap_response_arg_text(resp: &ImapResponse, index: Int) -> Str {
  let k: Vec[Int] = resp.kinds;
  let d: Vec[Int] = resp.depths;
  let t: Vec[Str] = resp.texts;
  return _top_text_of(&t, &k, &d, index);
}

/// Number of flat argument elements (list markers included).
pub fn imap_response_element_count(resp: &ImapResponse) -> Int {
  let v: Vec[Int] = resp.kinds;
  return v.len();
}

/// Kind of element `index` (IMAP_ARG_*), or -1 when out of range.
pub fn imap_response_element_kind(resp: &ImapResponse, index: Int) -> Int {
  let v: Vec[Int] = resp.kinds;
  return _vec_int_at(&v, index);
}

/// Decoded text of element `index`, or "" when out of range.
pub fn imap_response_element_text(resp: &ImapResponse, index: Int) -> Str {
  let v: Vec[Str] = resp.texts;
  return _vec_str_at(&v, index);
}

/// List nesting depth of element `index`, or -1 when out of range.
pub fn imap_response_element_depth(resp: &ImapResponse, index: Int) -> Int {
  let v: Vec[Int] = resp.depths;
  return _vec_int_at(&v, index);
}

/// Absolute byte offset of element `index` in the caller's buffer, or -1.
pub fn imap_response_element_offset(resp: &ImapResponse, index: Int) -> Int {
  let v: Vec[Int] = resp.offsets;
  return _vec_int_at(&v, index);
}
