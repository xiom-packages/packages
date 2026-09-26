// XIOM -- xiom.smtp: SMTP protocol codec (RFC 5321 grammar subset)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: implement the xiom.smtp package as a real, tested, pure-XIOM
// codec for SMTP command lines and reply blocks. Non-goals: no sockets and no
// session state, no DATA content parsing (sibling xiom.eml), no AUTH mechanism
// logic, no TLS.
//
// Wire model (RFC 5321 sections 4.1.1 and 4.2; the exact grammar and the
// canonicalization rules are pinned in SPEC.md):
//
//   command  = verb [ SP argument ] CRLF
//   verb     = EHLO / HELO / MAIL / RCPT / DATA / RSET / NOOP / QUIT /
//              STARTTLS / AUTH / VRFY / EXPN / HELP
//   reply    = *( code "-" text CRLF ) ( code [ SP text ] CRLF )
//
// A parsed command is a flat Cmd: `verb` is the canonical uppercase verb
// (parsing is case-insensitive), `arg` is the argument text verbatim, and for
// MAIL/RCPT `path` holds the "<...>" path and `params` the ESMTP parameters.
// A parsed reply is a flat Resp: `code` and `klass` (code / 100, so 2..5 are
// the SMTP classes), `pool` is the line texts joined with CRLF and `spans`
// holds two Ints per line (start, end into pool) -- no Vec[StructType], and
// no parallel-Vec drift because the line count is spans.len() / 2.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no self methods, no lambdas, no Vec[fn] and no
//     Vec[StructType];
//   * Str values are never compared with `==` (BUG 17: `==` on a Str read
//     from a Vec[Str] element lowers to a pointer comparison); every
//     comparison routes through xiom.string.compare.str_compare;
//   * Vec[Str]/Vec[Int] element reads are bound with a typed `let` first;
//   * byte_at results are widened with `(string.byte_at(s, i) as Int) & 0xFF`
//     before any arithmetic;
//   * output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str;
//   * Ok/Err for Result[Cmd, Str] and Result[Resp, Str] are constructed only
//     in the tiny leaf helpers below (constructing a Result inside a larger
//     function miscompiles).

module xiom.smtp

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Byte constants (UInt8 for direct byte_at compares, Int for widened loops)
// ---------------------------------------------------------------------------

const _SMTP_CR: UInt8 = 13u8;
const _SMTP_LF: UInt8 = 10u8;
const _SMTP_SPACE: UInt8 = 32u8;
const _SMTP_DASH: UInt8 = 45u8;
const _SMTP_EQ: UInt8 = 61u8;

const _SMTP_I_TAB: Int = 9;
const _SMTP_I_SPACE: Int = 32;
const _SMTP_I_DQUOTE: Int = 34;
const _SMTP_I_DASH: Int = 45;
const _SMTP_I_DOT: Int = 46;
const _SMTP_I_LT: Int = 60;
const _SMTP_I_GT: Int = 62;
const _SMTP_I_AT: Int = 64;
const _SMTP_I_DEL: Int = 127;

// RFC 5321 section 4.5.3.1.5: a command line is at most 512 octets including
// the terminating CRLF, so the content cap is 512 - 2.
const _SMTP_MAX_COMMAND: Int = 512;
const _SMTP_MAX_CONTENT: Int = 510;

// Verb identifiers (Str comparisons inside _verb_id are byte-exact, so the
// argument must already be the canonical uppercase verb).
const _SMTP_V_UNKNOWN: Int = -1;
const _SMTP_V_EHLO: Int = 1;
const _SMTP_V_HELO: Int = 2;
const _SMTP_V_MAIL: Int = 3;
const _SMTP_V_RCPT: Int = 4;
const _SMTP_V_DATA: Int = 5;
const _SMTP_V_RSET: Int = 6;
const _SMTP_V_NOOP: Int = 7;
const _SMTP_V_QUIT: Int = 8;
const _SMTP_V_STARTTLS: Int = 9;
const _SMTP_V_AUTH: Int = 10;
const _SMTP_V_VRFY: Int = 11;
const _SMTP_V_EXPN: Int = 12;
const _SMTP_V_HELP: Int = 13;

// ---------------------------------------------------------------------------
// Result constructors (see the module header)
// ---------------------------------------------------------------------------

// Ok(c) for Result[Cmd, Str].
fn _ok_cmd(c: Cmd) -> Result[Cmd, Str] {
  return Ok(c);
}

// Err(m) for Result[Cmd, Str].
fn _err_cmd(m: Str) -> Result[Cmd, Str] {
  return Err(m);
}

// Ok(r) for Result[Resp, Str].
fn _ok_resp(r: Resp) -> Result[Resp, Str] {
  return Ok(r);
}

// Err(m) for Result[Resp, Str].
fn _err_resp(m: Str) -> Result[Resp, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// One parsed SMTP command. `verb` is the canonical uppercase verb (parsing
/// is case-insensitive); `arg` is the argument text after the verb, verbatim
/// except that surrounding spaces are trimmed; `path` is the "<...>" path of
/// a MAIL/RCPT command ("" otherwise); `params` are the ESMTP parameters of a
/// MAIL/RCPT command in order (empty otherwise).
pub type Cmd = {
  verb: Str;
  arg: Str;
  path: Str;
  params: Vec[Str];
}

/// One parsed SMTP reply block. `code` is 100..599 and `klass` is
/// code / 100 (2..5 for the SMTP classes). `pool` holds the line texts joined
/// with CRLF and `spans` holds two Ints per line (start, end into pool), so
/// the line count is spans.len() / 2 and there is no parallel-Vec drift.
/// All lines of a block share `code` (a differing code is
/// Err("smtp: multiline code mismatch: <line>")).
pub type Resp = {
  code: Int;
  klass: Int;
  pool: Str;
  spans: Vec[Int];
}

// ---------------------------------------------------------------------------
// Byte and text helpers
// ---------------------------------------------------------------------------

// ASCII uppercase of byte c widened to 0..255 (non-letters unchanged).
fn _upper_byte(c: Int) -> Int {
  if c >= 97 && c <= 122 {
    return c - 32;
  }
  return c;
}

// ASCII-uppercase every byte of s (verbs are ASCII; other bytes pass through,
// so the byte length is preserved).
fn _upper_ascii(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let c = (string.byte_at(s, i) as Int) & 0xFF;
    out.push(_upper_byte(c) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// True when a and b are byte-equal (BUG 17 workaround: str_compare, not `==`).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when s starts with prefix, comparing ASCII letters case-insensitively.
fn _starts_with_ci(s: Str, prefix: Str) -> Bool {
  if prefix.len() > s.len() {
    return false;
  }
  var i = 0;
  while i < prefix.len() {
    let a = (string.byte_at(s, i) as Int) & 0xFF;
    let b = (string.byte_at(prefix, i) as Int) & 0xFF;
    if _upper_byte(a) != _upper_byte(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when s carries any C0 control byte (below space, TAB included) or DEL.
// CR and LF reach here only when they appear inside a command content, which
// is exactly the "control byte in command" case.
fn _has_control(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b < _SMTP_I_SPACE || b == _SMTP_I_DEL {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when reply text `s` carries a byte that RFC 5321 forbids in a reply
// text string: TAB (9) and bytes 32..126 pass, every other C0 byte and DEL is
// rejected. Bytes >= 128 pass through (UTF-8 is the caller's business).
fn _has_bad_text_control(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b < _SMTP_I_SPACE && b != _SMTP_I_TAB {
      return true;
    }
    if b == _SMTP_I_DEL {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Left-strip ASCII spaces.
fn _lstrip_spaces(s: Str) -> Str {
  var i = 0;
  while i < s.len() && string.byte_at(s, i) == _SMTP_SPACE {
    i = i + 1;
  }
  if i == 0 {
    return s;
  }
  return string.str_slice(s, i, s.len());
}

// Right-strip ASCII spaces.
fn _rstrip_spaces(s: Str) -> Str {
  var n = s.len();
  while n > 0 && string.byte_at(s, n - 1) == _SMTP_SPACE {
    n = n - 1;
  }
  if n == s.len() {
    return s;
  }
  return string.str_slice(s, 0, n);
}

// Strip spaces on both sides.
fn _trim_spaces(s: Str) -> Str {
  return _rstrip_spaces(_lstrip_spaces(s));
}

// Index of the first byte `target` in [from, end), or -1.
fn _find_byte(s: Str, from: Int, end: Int, target: UInt8) -> Int {
  var i = from;
  while i < end {
    if string.byte_at(s, i) == target {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Decimal text of v (used in error messages).
fn _int_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_int(&mut out, v);
  return builder.sb_to_str(&out);
}

// Canonical uppercase verb -> verb identifier.
fn _verb_id(v: Str) -> Int {
  if _streq(v, "EHLO") {
    return _SMTP_V_EHLO;
  }
  if _streq(v, "HELO") {
    return _SMTP_V_HELO;
  }
  if _streq(v, "MAIL") {
    return _SMTP_V_MAIL;
  }
  if _streq(v, "RCPT") {
    return _SMTP_V_RCPT;
  }
  if _streq(v, "DATA") {
    return _SMTP_V_DATA;
  }
  if _streq(v, "RSET") {
    return _SMTP_V_RSET;
  }
  if _streq(v, "NOOP") {
    return _SMTP_V_NOOP;
  }
  if _streq(v, "QUIT") {
    return _SMTP_V_QUIT;
  }
  if _streq(v, "STARTTLS") {
    return _SMTP_V_STARTTLS;
  }
  if _streq(v, "AUTH") {
    return _SMTP_V_AUTH;
  }
  if _streq(v, "VRFY") {
    return _SMTP_V_VRFY;
  }
  if _streq(v, "EXPN") {
    return _SMTP_V_EXPN;
  }
  if _streq(v, "HELP") {
    return _SMTP_V_HELP;
  }
  return _SMTP_V_UNKNOWN;
}

// ---------------------------------------------------------------------------
// Command parsing and building helpers
// ---------------------------------------------------------------------------

// "" when p is a legal ESMTP parameter, else "smtp: bad path: ...". The
// keyword before '=' is 1* (ALPHA / DIGIT / "-"); the value after '=' is
// non-empty and printable ASCII (33..126); a value-less parameter is legal.
fn _validate_param(p: Str) -> Str {
  if p.len() == 0 {
    return "smtp: bad path: empty parameter";
  }
  let eq = _find_byte(p, 0, p.len(), _SMTP_EQ);
  var kw_end = p.len();
  if eq >= 0 {
    kw_end = eq;
  }
  if kw_end == 0 {
    return "smtp: bad path: empty parameter keyword: " + p;
  }
  var i = 0;
  while i < kw_end {
    let b = (string.byte_at(p, i) as Int) & 0xFF;
    let is_upper = b >= 65 && b <= 90;
    let is_lower = b >= 97 && b <= 122;
    let is_digit = b >= 48 && b <= 57;
    if !is_upper && !is_lower && !is_digit && b != _SMTP_I_DASH {
      return "smtp: bad path: malformed parameter: " + p;
    }
    i = i + 1;
  }
  if eq >= 0 {
    if eq + 1 >= p.len() {
      return "smtp: bad path: empty parameter value: " + p;
    }
    var j = eq + 1;
    while j < p.len() {
      let b = (string.byte_at(p, j) as Int) & 0xFF;
      if b < 33 || b > 126 {
        return "smtp: bad path: malformed parameter: " + p;
      }
      j = j + 1;
    }
  }
  return "";
}

// Fill c.path and c.params from c.arg ("FROM:<path> [params]" for MAIL,
// "TO:<path> [params]" for RCPT). Returns "" on success or an
// "smtp: bad path: ..." message.
//
// Decisions (pinned in SPEC.md):
//   * the FROM:/TO: keyword is matched case-insensitively and spaces after
//     the colon are skipped;
//   * the path is the "<...>" byte range; inside a double-quoted local part a
//     '>' does not close it and spaces do not split parameters (no
//     backslash-escape handling: a quoted-pair is not decoded);
//   * a path whose inner text starts with '@' is a source route and is
//     rejected ("source routes are not supported");
//   * "MAIL FROM:<>" is the null reverse-path and is accepted; "RCPT TO:<>"
//     is rejected ("empty forward-path");
//   * the path must be followed by end of text or a space; parameters are
//     space-separated tokens validated by _validate_param.
fn _fill_path(c: &mut Cmd, vid: Int) -> Str {
  let arg: Str = c.arg;
  let alen = arg.len();
  var kw_ok = false;
  if vid == _SMTP_V_MAIL {
    kw_ok = _starts_with_ci(arg, "from:");
  } else {
    kw_ok = _starts_with_ci(arg, "to:");
  }
  if !kw_ok {
    if vid == _SMTP_V_MAIL {
      return "smtp: bad path: missing FROM:";
    }
    return "smtp: bad path: missing TO:";
  }
  var i = 5;
  if vid == _SMTP_V_RCPT {
    i = 3;
  }
  while i < alen && ((string.byte_at(arg, i) as Int) & 0xFF) == _SMTP_I_SPACE {
    i = i + 1;
  }
  if i >= alen {
    return "smtp: bad path: missing path";
  }
  if ((string.byte_at(arg, i) as Int) & 0xFF) != _SMTP_I_LT {
    return "smtp: bad path: expected '<'";
  }
  let path_start = i;
  i = i + 1;
  let inner_start = i;
  var in_quotes = false;
  while i < alen {
    let b = (string.byte_at(arg, i) as Int) & 0xFF;
    if in_quotes {
      if b == _SMTP_I_DQUOTE {
        in_quotes = false;
      }
      i = i + 1;
    } elif b == _SMTP_I_DQUOTE {
      in_quotes = true;
      i = i + 1;
    } elif b == _SMTP_I_GT {
      break;
    } else {
      i = i + 1;
    }
  }
  if i >= alen {
    return "smtp: bad path: unterminated '<'";
  }
  let inner = string.str_slice(arg, inner_start, i);
  if inner.len() > 0 && ((string.byte_at(inner, 0) as Int) & 0xFF) == _SMTP_I_AT {
    return "smtp: bad path: source routes are not supported";
  }
  if vid == _SMTP_V_RCPT && inner.len() == 0 {
    return "smtp: bad path: empty forward-path";
  }
  c.path = string.str_slice(arg, path_start, i + 1);
  i = i + 1;
  if i < alen && ((string.byte_at(arg, i) as Int) & 0xFF) != _SMTP_I_SPACE {
    return "smtp: bad path: path must be followed by a space";
  }
  while i < alen {
    while i < alen && ((string.byte_at(arg, i) as Int) & 0xFF) == _SMTP_I_SPACE {
      i = i + 1;
    }
    if i >= alen {
      break;
    }
    let pstart = i;
    while i < alen && ((string.byte_at(arg, i) as Int) & 0xFF) != _SMTP_I_SPACE {
      i = i + 1;
    }
    let p = string.str_slice(arg, pstart, i);
    let perr = _validate_param(p);
    if perr.len() > 0 {
      return perr;
    }
    c.params.push(p);
  }
  return "";
}

// Finish a command from an already canonical verb and a trimmed argument.
// MAIL/RCPT require the FROM:/TO: keyword (matched case-insensitively),
// canonicalize it to uppercase, run the path grammar and re-render the
// argument canonically from the parsed path and parameters;
// DATA/RSET/QUIT/STARTTLS take no argument; AUTH needs a mechanism;
// EHLO/HELO/NOOP/VRFY/EXPN/HELP take any argument (possibly empty) verbatim.
fn _make_cmd(vid: Int, verb: Str, arg: Str) -> Result[Cmd, Str] {
  var c = Cmd{ verb: verb; arg: arg; path: ""; params: Vec[Str].new() };
  if vid == _SMTP_V_MAIL || vid == _SMTP_V_RCPT {
    var kw = "FROM:";
    var klen = 5;
    if vid == _SMTP_V_RCPT {
      kw = "TO:";
      klen = 3;
    }
    if !_starts_with_ci(arg, kw) {
      return _err_cmd("smtp: bad path: missing " + kw);
    }
    let rest = _lstrip_spaces(string.str_slice(arg, klen, arg.len()));
    c.arg = kw + rest;
    let perr = _fill_path(&mut c, vid);
    if perr.len() > 0 {
      return _err_cmd(perr);
    }
    c.arg = _assemble_arg(kw, c.path, &c.params);
    return _ok_cmd(c);
  }
  if vid == _SMTP_V_DATA || vid == _SMTP_V_RSET || vid == _SMTP_V_QUIT || vid == _SMTP_V_STARTTLS {
    if arg.len() > 0 {
      return _err_cmd("smtp: bad verb: " + verb + " takes no argument");
    }
    return _ok_cmd(c);
  }
  if vid == _SMTP_V_AUTH {
    if arg.len() == 0 {
      return _err_cmd("smtp: bad verb: AUTH requires a mechanism");
    }
    return _ok_cmd(c);
  }
  return _ok_cmd(c);
}

// "FROM:<path> p1 p2" / "TO:<path> p1 p2" from the parts (no validation).
fn _assemble_arg(kw: Str, path: Str, params: &Vec[Str]) -> Str {
  var arg = kw + path;
  var i = 0;
  while i < params.len() {
    let p: Str = params[i];
    arg = arg + " " + p;
    i = i + 1;
  }
  return arg;
}

// ---------------------------------------------------------------------------
// Reply helpers
// ---------------------------------------------------------------------------

// Number of reply lines (spans holds two Ints per line).
fn _line_count(r: &Resp) -> Int {
  return r.spans.len() / 2;
}

// Append one line text to the flat pool/span storage of r.
fn _push_resp_line(r: &mut Resp, t: Str) {
  let cur: Str = r.pool;
  if r.spans.len() > 0 {
    r.pool = cur + "\r\n";
  }
  let cur2: Str = r.pool;
  let start = cur2.len();
  r.pool = cur2 + t;
  let cur3: Str = r.pool;
  r.spans.push(start);
  r.spans.push(cur3.len());
}

// Append the three ASCII digits of a code in 100..599 to out.
fn _push_code3(out: &mut Vec[UInt8], code: Int) {
  out.push((48 + (code / 100)) as UInt8);
  out.push((48 + ((code / 10) % 10)) as UInt8);
  out.push((48 + (code % 10)) as UInt8);
}

// ---------------------------------------------------------------------------
// Public API -- commands
// ---------------------------------------------------------------------------

/// Maximum command line length in octets including the terminating CRLF
/// (RFC 5321 section 4.5.3.1.5). Command content is capped at this minus 2.
/// Params: none.
/// Returns: 512.
/// Error case: none.
/// Complexity: O(1).
pub fn smtp_command_limit() -> Int {
  return _SMTP_MAX_COMMAND;
}

/// Parse one SMTP command line.
/// Params: line - one command, which MUST be terminated by CRLF.
/// Grammar: verb [ SP argument ] CRLF; verbs are matched case-insensitively
/// against EHLO, HELO, MAIL, RCPT, DATA, RSET, NOOP, QUIT, STARTTLS, AUTH,
/// VRFY, EXPN and HELP. MAIL/RCPT require "FROM:"/"TO:" followed by a
/// "<...>" path (quoted local parts pass through; source routes and, for
/// RCPT, the null forward-path are rejected) and optional ESMTP parameters;
/// DATA/RSET/QUIT/STARTTLS take no argument; AUTH requires a mechanism;
/// NOOP/VRFY/EXPN/HELP (and EHLO/HELO) take their argument verbatim.
/// Returns: Ok(Cmd) with the canonical uppercase verb, the trimmed argument
/// text and, for MAIL/RCPT, the path and parameters.
/// Error case: Err("smtp: missing CRLF") without a CRLF terminator;
/// Err("smtp: command too long: <n>") past 512 octets;
/// Err("smtp: control byte in command") for a C0/DEL byte in the content;
/// Err("smtp: bad verb: <verb>") for an unknown verb or a command form error;
/// Err("smtp: bad path: ...") for a malformed MAIL/RCPT path or parameter.
/// Complexity: O(len(line)).
pub fn cmd_parse(line: Str) -> Result[Cmd, Str] {
  let n = line.len();
  if n < 2 {
    return _err_cmd("smtp: missing CRLF");
  }
  if string.byte_at(line, n - 2) != _SMTP_CR || string.byte_at(line, n - 1) != _SMTP_LF {
    return _err_cmd("smtp: missing CRLF");
  }
  let clen = n - 2;
  if clen > _SMTP_MAX_CONTENT {
    return _err_cmd("smtp: command too long: " + _int_str(n));
  }
  let content = string.str_slice(line, 0, clen);
  if _has_control(content) {
    return _err_cmd("smtp: control byte in command");
  }
  let sp = _find_byte(content, 0, clen, _SMTP_SPACE);
  var verb_raw = content;
  var arg = "";
  if sp >= 0 {
    verb_raw = string.str_slice(content, 0, sp);
    arg = _trim_spaces(string.str_slice(content, sp + 1, clen));
  }
  let verb = _upper_ascii(verb_raw);
  let vid = _verb_id(verb);
  if vid == _SMTP_V_UNKNOWN {
    return _err_cmd("smtp: bad verb: " + verb_raw);
  }
  return _make_cmd(vid, verb, arg);
}

/// Build one SMTP command from a verb and a full argument text.
/// Params: verb - the command verb, any case, trimmed; arg - the argument
/// text, trimmed; for MAIL/RCPT it must be the full "FROM:<path> [params]" /
/// "TO:<path> [params]" form (the convenience builders cmd_mail/cmd_rcpt
/// assemble it).
/// Returns: Ok(Cmd) with the canonical uppercase verb; cmd_emit renders the
/// canonical CRLF-framed line.
/// Error case: Err("smtp: bad verb: <verb>") for an unknown verb, an argument
/// on DATA/RSET/QUIT/STARTTLS, or an AUTH without a mechanism;
/// Err("smtp: control byte in command") for a C0/DEL byte in the argument;
/// Err("smtp: bad path: ...") for a malformed MAIL/RCPT argument.
/// Complexity: O(total length).
pub fn cmd_build(verb: Str, arg: Str) -> Result[Cmd, Str] {
  let v = _upper_ascii(_trim_spaces(verb));
  let vid = _verb_id(v);
  if vid == _SMTP_V_UNKNOWN {
    return _err_cmd("smtp: bad verb: " + verb);
  }
  let a = _trim_spaces(arg);
  if _has_control(a) {
    return _err_cmd("smtp: control byte in command");
  }
  return _make_cmd(vid, v, a);
}

/// Build an EHLO command for `domain`.
/// Params: domain - the client domain; must not be empty.
/// Returns: Ok(Cmd) equivalent to cmd_build("EHLO", domain).
/// Error case: Err("smtp: bad verb: EHLO requires a domain") for an empty
/// (or spaces-only) domain; plus every error of cmd_build.
/// Complexity: O(len(domain)).
pub fn cmd_ehlo(domain: Str) -> Result[Cmd, Str] {
  let d = _trim_spaces(domain);
  if d.len() == 0 {
    return _err_cmd("smtp: bad verb: EHLO requires a domain");
  }
  return cmd_build("EHLO", d);
}

/// Build a HELO command for `domain`.
/// Params: domain - the client domain; must not be empty.
/// Returns: Ok(Cmd) equivalent to cmd_build("HELO", domain).
/// Error case: Err("smtp: bad verb: HELO requires a domain") for an empty
/// (or spaces-only) domain; plus every error of cmd_build.
/// Complexity: O(len(domain)).
pub fn cmd_helo(domain: Str) -> Result[Cmd, Str] {
  let d = _trim_spaces(domain);
  if d.len() == 0 {
    return _err_cmd("smtp: bad verb: HELO requires a domain");
  }
  return cmd_build("HELO", d);
}

/// Build a MAIL command (envelope sender).
/// Params: reverse_path - the path with its angle brackets ("<>" is the null
/// reverse-path); params - the ESMTP parameters in order, possibly empty.
/// Returns: Ok(Cmd) whose `path` is the "<...>" text and whose `params` are
/// the validated parameters; cmd_emit renders "MAIL FROM:<...> p1 p2\r\n".
/// Error case: every error of cmd_build (in particular
/// Err("smtp: bad path: missing FROM:") cannot happen here, while a malformed
/// path or parameter yields Err("smtp: bad path: ...")).
/// Complexity: O(total length).
pub fn cmd_mail(reverse_path: Str, params: &Vec[Str]) -> Result[Cmd, Str] {
  let arg = _assemble_arg("FROM:", reverse_path, params);
  return cmd_build("MAIL", arg);
}

/// Build a RCPT command (envelope recipient).
/// Params: forward_path - the path with its angle brackets; the null path
/// "<>" is rejected (RCPT needs a real forward-path); params - the ESMTP
/// parameters in order, possibly empty.
/// Returns: Ok(Cmd) whose `path` is the "<...>" text and whose `params` are
/// the validated parameters; cmd_emit renders "RCPT TO:<...> p1 p2\r\n".
/// Error case: Err("smtp: bad path: empty forward-path") for "<>"; plus every
/// error of cmd_build.
/// Complexity: O(total length).
pub fn cmd_rcpt(forward_path: Str, params: &Vec[Str]) -> Result[Cmd, Str] {
  let arg = _assemble_arg("TO:", forward_path, params);
  return cmd_build("RCPT", arg);
}

/// Build a NOOP command with an optional string.
/// Params: arg - the NOOP argument ("" for a bare NOOP).
/// Returns: Ok(Cmd) equivalent to cmd_build("NOOP", arg).
/// Error case: every error of cmd_build.
/// Complexity: O(len(arg)).
pub fn cmd_noop(arg: Str) -> Result[Cmd, Str] {
  return cmd_build("NOOP", _trim_spaces(arg));
}

/// Build an AUTH command.
/// Params: mechanism - the SASL mechanism name, e.g. "PLAIN"; must not be
/// empty; initial_response - the optional initial response, kept verbatim
/// ("" omits it, "=" is the empty-response form).
/// Returns: Ok(Cmd); cmd_emit renders "AUTH PLAIN <response>\r\n".
/// Error case: Err("smtp: bad verb: AUTH requires a mechanism") for an empty
/// mechanism; every error of cmd_build.
/// Complexity: O(total length).
pub fn cmd_auth(mechanism: Str, initial_response: Str) -> Result[Cmd, Str] {
  let m = _trim_spaces(mechanism);
  if m.len() == 0 {
    return _err_cmd("smtp: bad verb: AUTH requires a mechanism");
  }
  let r = _trim_spaces(initial_response);
  var arg = m;
  if r.len() > 0 {
    arg = arg + " " + r;
  }
  return cmd_build("AUTH", arg);
}

/// Build a bare DATA command.
/// Params: none.
/// Returns: the Cmd for "DATA\r\n".
/// Error case: none.
/// Complexity: O(1).
pub fn cmd_data() -> Cmd {
  return Cmd{ verb: "DATA"; arg: ""; path: ""; params: Vec[Str].new() };
}

/// Build a bare RSET command.
/// Params: none.
/// Returns: the Cmd for "RSET\r\n".
/// Error case: none.
/// Complexity: O(1).
pub fn cmd_rset() -> Cmd {
  return Cmd{ verb: "RSET"; arg: ""; path: ""; params: Vec[Str].new() };
}

/// Build a bare QUIT command.
/// Params: none.
/// Returns: the Cmd for "QUIT\r\n".
/// Error case: none.
/// Complexity: O(1).
pub fn cmd_quit() -> Cmd {
  return Cmd{ verb: "QUIT"; arg: ""; path: ""; params: Vec[Str].new() };
}

/// Build a bare STARTTLS command.
/// Params: none.
/// Returns: the Cmd for "STARTTLS\r\n".
/// Error case: none.
/// Complexity: O(1).
pub fn cmd_starttls() -> Cmd {
  return Cmd{ verb: "STARTTLS"; arg: ""; path: ""; params: Vec[Str].new() };
}

/// Render one command to its canonical wire form.
/// Params: c - a command from cmd_parse or a builder.
/// Returns: "VERB" or "VERB argument" plus CRLF. The verb is the canonical
/// uppercase form; runs of spaces between verb and argument are normalized to
/// one and surrounding argument spaces are dropped, so parse->emit is
/// byte-exact for canonically spaced input and stable afterwards.
/// Error case: none (the Cmd invariants are maintained by this module).
/// Complexity: O(total length).
pub fn cmd_emit(c: &Cmd) -> Str {
  var out = Vec[UInt8].new();
  let v: Str = c.verb;
  builder.sb_push_str(&mut out, v);
  let a: Str = c.arg;
  if a.len() > 0 {
    out.push(_SMTP_SPACE);
    builder.sb_push_str(&mut out, a);
  }
  out.push(_SMTP_CR);
  out.push(_SMTP_LF);
  return builder.sb_to_str(&out);
}

/// Canonical uppercase verb of the command.
/// Params: c - the command.
/// Returns: the verb, e.g. "MAIL".
/// Error case: none.
/// Complexity: O(len(verb)).
pub fn cmd_name(c: &Cmd) -> Str {
  let v: Str = c.verb;
  return v;
}

/// Argument text of the command, verbatim after trimming.
/// Params: c - the command.
/// Returns: e.g. "FROM:<a@b> SIZE=100" for a MAIL command, "example.com" for
/// EHLO, "" for a bare DATA; for AUTH it holds "mechanism [initial-response]".
/// Error case: none.
/// Complexity: O(len(arg)).
pub fn cmd_argument(c: &Cmd) -> Str {
  let a: Str = c.arg;
  return a;
}

/// Path of a MAIL/RCPT command, with its angle brackets.
/// Params: c - the command.
/// Returns: the "<...>" path text ("" for every other verb).
/// Error case: none.
/// Complexity: O(len(path)).
pub fn cmd_path(c: &Cmd) -> Str {
  let p: Str = c.path;
  return p;
}

/// Number of ESMTP parameters on a MAIL/RCPT command.
/// Params: c - the command.
/// Returns: the parameter count (0 for every other verb).
/// Error case: none.
/// Complexity: O(1).
pub fn cmd_param_count(c: &Cmd) -> Int {
  return c.params.len();
}

/// ESMTP parameter `i` of a MAIL/RCPT command, in wire order.
/// Params: c - the command; i - zero-based index.
/// Returns: the parameter text (e.g. "SIZE=100"); "" when i is negative or
/// past the last parameter.
/// Error case: none.
/// Complexity: O(1).
pub fn cmd_param(c: &Cmd, i: Int) -> Str {
  if i < 0 || i >= c.params.len() {
    return "";
  }
  let p: Str = c.params[i];
  return p;
}

/// Case-insensitive comparison of the command verb with `name`, e.g.
/// cmd_verb_is(&c, "mail") is true for a parsed MAIL command.
/// Params: c - the command; name - the verb text to test.
/// Returns: true when the verbs match ignoring ASCII case.
/// Error case: none.
/// Complexity: O(min(len(verb), len(name))).
pub fn cmd_verb_is(c: &Cmd, name: Str) -> Bool {
  let v: Str = c.verb;
  return compare.str_eq_ignore_case(v, name);
}

// ---------------------------------------------------------------------------
// Public API -- replies
// ---------------------------------------------------------------------------

/// Parse one SMTP reply block.
/// Params: text - exactly one reply, which MUST be terminated by CRLF; a
/// single-line reply ends at its first final line and any bytes after it are
/// not consumed (the caller splits the stream).
/// Grammar: *( code "-" text CRLF ) ( code [ SP text ] CRLF ); all lines of a
/// block must carry the same code and every line before the last must use the
/// "-" separator. The code is three ASCII digits in 100..599 (bad ones are
/// Err); the text of the first line is what resp_text/resp_enhanced inspect.
/// Returns: Ok(Resp) with `code`, `klass` = code / 100, the line texts in the
/// flat pool/spans storage (line count = spans.len() / 2).
/// Error case: Err("smtp: missing CRLF") for a missing/bare terminator;
/// Err("smtp: bad code digits: <line>") for a malformed or out-of-range code
/// or a bad separator byte; Err("smtp: multiline code mismatch: <line>") when
/// a continuation line carries a different code;
/// Err("smtp: unterminated multiline") when the input ends on a
/// continuation line;
/// Err("smtp: control byte in response") for a forbidden byte in the text.
/// Complexity: O(len(text)).
pub fn resp_parse(text: Str) -> Result[Resp, Str] {
  let n = text.len();
  if n < 2 {
    return _err_resp("smtp: missing CRLF");
  }
  if string.byte_at(text, n - 2) != _SMTP_CR || string.byte_at(text, n - 1) != _SMTP_LF {
    return _err_resp("smtp: missing CRLF");
  }
  var r = Resp{ code: 0; klass: 0; pool: ""; spans: Vec[Int].new() };
  var line_start = 0;
  var i = 0;
  var first = true;
  var done = false;
  while i < n && !done {
    let b = string.byte_at(text, i);
    if b == _SMTP_CR {
      if i + 1 >= n || string.byte_at(text, i + 1) != _SMTP_LF {
        return _err_resp("smtp: missing CRLF");
      }
      let line = string.str_slice(text, line_start, i);
      let llen = line.len();
      if llen < 3 {
        return _err_resp("smtp: bad code digits: " + line);
      }
      var code = 0;
      var bad = false;
      var k = 0;
      while k < 3 {
        let d = (string.byte_at(line, k) as Int) & 0xFF;
        if d < 48 || d > 57 {
          bad = true;
          break;
        }
        code = code * 10 + (d - 48);
        k = k + 1;
      }
      if bad || code < 100 || code > 599 {
        return _err_resp("smtp: bad code digits: " + line);
      }
      if first {
        r.code = code;
        r.klass = code / 100;
      } elif code != r.code {
        return _err_resp("smtp: multiline code mismatch: " + line);
      }
      var sep = 0;
      if llen > 3 {
        let b3 = (string.byte_at(line, 3) as Int) & 0xFF;
        if b3 == _SMTP_I_DASH {
          sep = 1;
        } elif b3 == _SMTP_I_SPACE {
          sep = 2;
        } else {
          return _err_resp("smtp: bad code digits: " + line);
        }
      }
      var tstart = llen;
      if llen > 3 {
        tstart = 4;
      }
      let lt = string.str_slice(line, tstart, llen);
      if _has_bad_text_control(lt) {
        return _err_resp("smtp: control byte in response");
      }
      _push_resp_line(&mut r, lt);
      first = false;
      if sep != 1 {
        done = true;
      }
      i = i + 2;
      line_start = i;
    } elif b == _SMTP_LF {
      return _err_resp("smtp: missing CRLF");
    } else {
      i = i + 1;
    }
  }
  if !done {
    return _err_resp("smtp: unterminated multiline");
  }
  return _ok_resp(r);
}

/// Build one SMTP reply block.
/// Params: code - the reply code, 100..599; lines - the reply texts, at least
/// one; a single entry builds a single-line reply, more entries build a
/// multiline reply whose last line carries the final "SP text" form.
/// Returns: Ok(Resp) with `klass` = code / 100 and the flat pool/spans
/// storage; resp_emit renders the canonical CRLF block.
/// Error case: Err("smtp: bad code digits: <code>") when code is outside
/// 100..599; Err("smtp: unterminated multiline: response has no lines") for
/// an empty lines vector; Err("smtp: control byte in response") for a
/// forbidden byte in a line text (TAB is legal).
/// Complexity: O(total length).
pub fn resp_build(code: Int, lines: &Vec[Str]) -> Result[Resp, Str] {
  if code < 100 || code > 599 {
    return _err_resp("smtp: bad code digits: " + _int_str(code));
  }
  if lines.len() == 0 {
    return _err_resp("smtp: unterminated multiline: response has no lines");
  }
  var r = Resp{ code: code; klass: code / 100; pool: ""; spans: Vec[Int].new() };
  var i = 0;
  while i < lines.len() {
    let t: Str = lines[i];
    if _has_bad_text_control(t) {
      return _err_resp("smtp: control byte in response");
    }
    _push_resp_line(&mut r, t);
    i = i + 1;
  }
  return _ok_resp(r);
}

/// Render one reply block to its canonical wire form.
/// Params: r - a reply from resp_parse or resp_build.
/// Returns: every non-final line as "NNN-text\r\n", the final line as
/// "NNN text\r\n" when its text is non-empty and "NNN\r\n" when it is empty;
/// parse->emit is byte-exact for canonical input (a final line written with a
/// trailing SP but empty text canonicalizes to the bare "NNN" form).
/// Error case: none (the Resp invariants are maintained by this module).
/// Complexity: O(total length).
pub fn resp_emit(r: &Resp) -> Str {
  var out = Vec[UInt8].new();
  let count = _line_count(r);
  var i = 0;
  while i < count {
    _push_code3(&mut out, r.code);
    let t: Str = resp_line(r, i);
    if i + 1 < count {
      out.push(_SMTP_DASH);
      builder.sb_push_str(&mut out, t);
    } else {
      if t.len() > 0 {
        out.push(_SMTP_SPACE);
        builder.sb_push_str(&mut out, t);
      }
    }
    out.push(_SMTP_CR);
    out.push(_SMTP_LF);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Reply code (100..599).
/// Params: r - the reply.
/// Returns: the numeric code, e.g. 250.
/// Error case: none.
/// Complexity: O(1).
pub fn resp_code(r: &Resp) -> Int {
  return r.code;
}

/// Reply class: code / 100, so 2, 3, 4 or 5 for an SMTP reply.
/// Params: r - the reply.
/// Returns: the class digit.
/// Error case: none.
/// Complexity: O(1).
pub fn resp_class(r: &Resp) -> Int {
  return r.klass;
}

/// True when the reply was written as a multiline block.
/// Params: r - the reply.
/// Returns: true when spans.len() / 2 > 1.
/// Error case: none.
/// Complexity: O(1).
pub fn resp_is_multiline(r: &Resp) -> Bool {
  return _line_count(r) > 1;
}

/// Number of lines in the reply block.
/// Params: r - the reply.
/// Returns: the line count (1 for a single-line reply).
/// Error case: none.
/// Complexity: O(1).
pub fn resp_line_count(r: &Resp) -> Int {
  return _line_count(r);
}

/// Text of reply line `i` (the line text without the code and separator).
/// Params: r - the reply; i - zero-based line index.
/// Returns: the line text, e.g. "5.1.1 User unknown"; "" when i is negative
/// or past the last line.
/// Error case: none.
/// Complexity: O(len(line)).
pub fn resp_line(r: &Resp, i: Int) -> Str {
  if i < 0 || i >= _line_count(r) {
    return "";
  }
  let a: Int = r.spans[i * 2];
  let b: Int = r.spans[i * 2 + 1];
  return string.str_slice(r.pool, a, b);
}

/// Text of the first reply line (what single-line clients read).
/// Params: r - the reply.
/// Returns: resp_line(r, 0); "" for a reply with no lines.
/// Error case: none.
/// Complexity: O(len(line)).
pub fn resp_text(r: &Resp) -> Str {
  return resp_line(r, 0);
}

/// Enhanced status code at the start of the first line text, when present.
/// Params: r - the reply.
/// Returns: the "x.y.z" text (class: 1 digit, subject and detail: 1..3
/// digits) when the first line text starts with it and it is followed by a
/// space or the end of the text; "" otherwise. Only the first line is
/// inspected.
/// Error case: none.
/// Complexity: O(len(first line)).
pub fn resp_enhanced(r: &Resp) -> Str {
  let t = resp_line(r, 0);
  let n = t.len();
  var i = 0;
  var part = 0;
  while part < 3 {
    let dstart = i;
    while i < n {
      let b = (string.byte_at(t, i) as Int) & 0xFF;
      if b >= 48 && b <= 57 {
        i = i + 1;
      } else {
        break;
      }
    }
    let dlen = i - dstart;
    if dlen < 1 || dlen > 3 {
      return "";
    }
    if part == 0 && dlen != 1 {
      return "";
    }
    part = part + 1;
    if part < 3 {
      if i >= n {
        return "";
      }
      if ((string.byte_at(t, i) as Int) & 0xFF) != _SMTP_I_DOT {
        return "";
      }
      i = i + 1;
    }
  }
  if i < n && ((string.byte_at(t, i) as Int) & 0xFF) != _SMTP_I_SPACE {
    return "";
  }
  return string.str_slice(t, 0, i);
}

/// True when resp_enhanced(r) is non-empty.
/// Params: r - the reply.
/// Returns: true when the first line text starts with an x.y.z code.
/// Error case: none.
/// Complexity: O(len(first line)).
pub fn resp_has_enhanced(r: &Resp) -> Bool {
  return resp_enhanced(r).len() > 0;
}
