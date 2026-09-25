// XIOM -- xiom.irc: IRC message codec (RFC 1459/2812 subset plus IRCv3 tags)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: implement the xiom.irc package as a real, tested, pure-XIOM
// message codec: parse, prefix split, IRCv3 message tags, building, numeric
// replies and wire round-trips. Non-goals: no networking, no client/server
// state (see SPEC.md).
//
// Wire model (RFC 1459/2812 section 2.3.1, extended by the IRCv3 message-tags
// specification; the exact grammar is pinned in SPEC.md):
//
//   [ '@' tags SP ] [ ':' prefix SP ] command [ SP middle ]* [ SP ':' trailing ] CRLF
//
// A parsed message is a flat IrcMessage. tag_names/tag_values/tag_flags are
// index-aligned (`tag_flags[i] == 1` when the tag carried "=value", even an
// empty one); `prefix` is the raw prefix without the ':' and nick/user/host
// are its split parts; `params` holds the middle parameters only; `trailing`
// holds the trailing text and `has_trailing` distinguishes "CMD :" (empty
// trailing) from "CMD" (no trailing). Vec[StructType] is unsupported in this
// compiler, so the message and prefix models are deliberately flat.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no self methods, no lambdas, no Vec[StructType];
//   * Str values are never compared with `==` (BUG 17: `==` on a Str read from
//     a Vec[Str] element lowers to a pointer comparison); tag lookups route
//     through xiom.string.compare.str_compare;
//   * Vec[Str]/Vec[Int] element reads are bound with a typed `let` first;
//   * byte_at results are widened with `as Int` before arithmetic;
//   * output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str;
//   * Ok/Err for Result[...] are constructed only in the tiny leaf helpers
//     below (constructing a Result inside a larger function miscompiles).

module xiom.irc

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Byte constants
// ---------------------------------------------------------------------------

const _IRC_LF: UInt8 = 10u8;
const _IRC_CR: UInt8 = 13u8;
const _IRC_SPACE: UInt8 = 32u8;
const _IRC_BANG: UInt8 = 33u8;
const _IRC_COLON: UInt8 = 58u8;
const _IRC_SEMI: UInt8 = 59u8;
const _IRC_EQ: UInt8 = 61u8;
const _IRC_AT: UInt8 = 64u8;
const _IRC_BACKSLASH: UInt8 = 92u8;
const _IRC_LOWER_N: UInt8 = 110u8;
const _IRC_LOWER_R: UInt8 = 114u8;
const _IRC_LOWER_S: UInt8 = 115u8;

// ---------------------------------------------------------------------------
// Result constructors (see the module header)
// ---------------------------------------------------------------------------

// Ok(m) for Result[IrcMessage, Str].
fn _ok_msg(m: IrcMessage) -> Result[IrcMessage, Str] {
  return Ok(m);
}

// Err(m) for Result[IrcMessage, Str].
fn _err_msg(m: Str) -> Result[IrcMessage, Str] {
  return Err(m);
}

// Ok(s) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
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

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// One split IRC prefix. `raw` is the prefix text without the leading ':';
/// `nick`, `user` and `host` are its parts (empty when absent). When the
/// prefix carries neither '!' nor '@' it is treated as a server name:
/// `is_server` is true and `nick` holds the whole text.
pub type IrcPrefix = {
  raw: Str;
  nick: Str;
  user: Str;
  host: Str;
  is_server: Bool;
}

/// One parsed IRC message. Invariants: the three tag vectors have equal
/// length; `has_prefix` implies `prefix != ""`; `params` holds the middle
/// parameters only (the trailing text is `trailing`, present exactly when
/// `has_trailing`). Tag names are case-sensitive opaque identifiers.
pub type IrcMessage = {
  tag_names: Vec[Str];
  tag_values: Vec[Str];
  tag_flags: Vec[Int];
  has_prefix: Bool;
  prefix: Str;
  nick: Str;
  user: Str;
  host: Str;
  is_server_prefix: Bool;
  command: Str;
  params: Vec[Str];
  has_trailing: Bool;
  trailing: Str;
}

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

// Index of the first `target` byte in [from, end), or -1.
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

// End of the first line: the index of the first CR or LF, or len(s) when the
// text carries neither.
fn _line_end(s: Str) -> Int {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _IRC_CR || b == _IRC_LF {
      return i;
    }
    i = i + 1;
  }
  return s.len();
}

// True when [from, to) holds no byte other than ASCII space.
fn _only_spaces(s: Str, from: Int, to: Int) -> Bool {
  var i = from;
  while i < to {
    if string.byte_at(s, i) != _IRC_SPACE {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// ASCII uppercase of byte `c` widened to 0..255 (non-letters unchanged).
// The command comparison uses uppercase mapping plus an integer byte compare;
// it never compares Str values read from a Vec.
fn _upper_byte(c: Int) -> Int {
  if c >= 97 && c <= 122 {
    return c - 32;
  }
  return c;
}

// Append the escaped wire form of tag value `v` to `out`: `;` -> "\:", the
// space -> "\s", the backslash -> "\\", CR -> "\r" and LF -> "\n"; every
// other byte passes through verbatim.
fn _push_tag_value(out: &mut Vec[UInt8], v: Str) {
  var i = 0;
  while i < v.len() {
    let b = string.byte_at(v, i);
    if b == _IRC_SEMI {
      builder.sb_push_str(out, "\\:");
    } elif b == _IRC_SPACE {
      builder.sb_push_str(out, "\\s");
    } elif b == _IRC_BACKSLASH {
      builder.sb_push_str(out, "\\\\");
    } elif b == _IRC_CR {
      builder.sb_push_str(out, "\\r");
    } elif b == _IRC_LF {
      builder.sb_push_str(out, "\\n");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
}

// Decode the IRCv3 escapes of a raw tag value. "\:" -> ';', "\s" -> space,
// "\\" -> backslash, "\r" -> CR, "\n" -> LF; an unknown escape drops the
// backslash and keeps the following byte; a lone trailing backslash is
// dropped (all three rules are pinned by the message-tags specification).
fn _unescape_tag(raw: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < raw.len() {
    let b = string.byte_at(raw, i);
    if b == _IRC_BACKSLASH {
      if i + 1 < raw.len() {
        let c = string.byte_at(raw, i + 1);
        if c == _IRC_COLON {
          out.push(_IRC_SEMI);
        } elif c == _IRC_LOWER_S {
          out.push(_IRC_SPACE);
        } elif c == _IRC_BACKSLASH {
          out.push(_IRC_BACKSLASH);
        } elif c == _IRC_LOWER_R {
          out.push(_IRC_CR);
        } elif c == _IRC_LOWER_N {
          out.push(_IRC_LF);
        } else {
          out.push(c);
        }
        i = i + 2;
      } else {
        i = i + 1;
      }
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// Decimal text of `v` (used only in error messages).
fn _int_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_int(&mut out, v);
  return builder.sb_to_str(&out);
}

// Zero-padded three-digit text of a numeric code in 0..999.
fn _num3(code: Int) -> Str {
  var out = Vec[UInt8].new();
  out.push((48 + (code / 100)) as UInt8);
  out.push((48 + ((code / 10) % 10)) as UInt8);
  out.push((48 + (code % 10)) as UInt8);
  return builder.sb_to_str(&out);
}

// Index of the last tag named `lname` (byte-exact, case-sensitive), or -1.
// Duplicate keys are legal on the wire and the message-tags specification
// says all but the final occurrence should be disregarded.
fn _tag_last_index(m: &IrcMessage, name: Str) -> Int {
  var i = m.tag_names.len() - 1;
  while i >= 0 {
    let k: Str = m.tag_names[i];
    if compare.str_compare(k, name) == 0 {
      return i;
    }
    i = i - 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

// Parse the tag section body [from, to) (the bytes after '@' up to the
// separating space) into `m`. Returns "" on success or an "irc: ..." message.
// A segment between ';' separators is a tag; empty segments are skipped, and
// a section with no tag at all is malformed. Key names are accepted verbatim
// (the message-tags specification forbids rejecting a message for an invalid
// key name), so "@=v" is a tag with an empty name and value "v".
fn _parse_tag_section(text: Str, from: Int, to: Int, m: &mut IrcMessage) -> Str {
  if from >= to {
    return "irc: empty tags";
  }
  var seg = from;
  var i = from;
  while i <= to {
    if i == to || string.byte_at(text, i) == _IRC_SEMI {
      if i > seg {
        let eq = _find_byte(text, seg, i, _IRC_EQ);
        if eq < 0 {
          m.tag_names.push(string.str_slice(text, seg, i));
          m.tag_values.push("");
          m.tag_flags.push(0);
        } else {
          let key = string.str_slice(text, seg, eq);
          let raw = string.str_slice(text, eq + 1, i);
          m.tag_names.push(key);
          m.tag_values.push(_unescape_tag(raw));
          m.tag_flags.push(1);
        }
      }
      seg = i + 1;
    }
    i = i + 1;
  }
  if m.tag_names.len() == 0 {
    return "irc: empty tags";
  }
  return "";
}

// ---------------------------------------------------------------------------
// Build validation
// ---------------------------------------------------------------------------

// "" when `cmd` is a non-empty run of ASCII letters/digits, else an error.
fn _validate_command(cmd: Str) -> Str {
  if cmd.len() == 0 {
    return "irc: empty command";
  }
  var i = 0;
  while i < cmd.len() {
    let b = (string.byte_at(cmd, i) as Int) & 0xFF;
    let is_upper = b >= 65 && b <= 90;
    let is_lower = b >= 97 && b <= 122;
    let is_digit = b >= 48 && b <= 57;
    if !is_upper && !is_lower && !is_digit {
      return "irc: invalid command: " + cmd;
    }
    i = i + 1;
  }
  return "";
}

// "" when `p` is a legal middle parameter: non-empty and free of spaces,
// CR/LF and a leading ':'.
fn _validate_param(p: Str) -> Str {
  if p.len() == 0 {
    return "irc: empty parameter";
  }
  let b0 = (string.byte_at(p, 0) as Int) & 0xFF;
  if b0 == 58 {
    return "irc: invalid parameter: " + p;
  }
  var i = 0;
  while i < p.len() {
    let b = (string.byte_at(p, i) as Int) & 0xFF;
    if b == 32 || b == 13 || b == 10 {
      return "irc: invalid parameter: " + p;
    }
    i = i + 1;
  }
  return "";
}

// "" when trailing text `t` carries no CR/LF (spaces and ':' are legal).
fn _validate_trailing(t: Str) -> Str {
  var i = 0;
  while i < t.len() {
    let b = (string.byte_at(t, i) as Int) & 0xFF;
    if b == 13 || b == 10 {
      return "irc: trailing contains a line break";
    }
    i = i + 1;
  }
  return "";
}

// "" when `p` is a legal prefix: non-empty and free of spaces and CR/LF.
fn _validate_prefix(p: Str) -> Str {
  var i = 0;
  while i < p.len() {
    let b = (string.byte_at(p, i) as Int) & 0xFF;
    if b == 32 || b == 13 || b == 10 {
      return "irc: invalid prefix: " + p;
    }
    i = i + 1;
  }
  return "";
}

// "" when `k` is a legal tag name for building: non-empty and free of
// spaces, ';', '=' and CR/LF. The IRCv3 key grammar (letters, digits,
// hyphens, optional '+' and vendor '/') is deliberately not enforced.
fn _validate_tag_name(k: Str) -> Str {
  if k.len() == 0 {
    return "irc: empty tag name";
  }
  var i = 0;
  while i < k.len() {
    let b = (string.byte_at(k, i) as Int) & 0xFF;
    if b == 32 || b == 59 || b == 61 || b == 13 || b == 10 {
      return "irc: invalid tag name: " + k;
    }
    i = i + 1;
  }
  return "";
}

// Validate every part of a message about to be built. Returns "" on success
// or the first "irc: ..." message in this order: tag counts, tag names,
// prefix, command, parameters, trailing.
fn _validate_build(tag_names: &Vec[Str], tag_values: &Vec[Str], prefix: Str, command: Str, params: &Vec[Str], trailing: Str, has_trailing: Bool) -> Str {
  if tag_names.len() != tag_values.len() {
    return "irc: tag name/value count mismatch";
  }
  var i = 0;
  while i < tag_names.len() {
    let k: Str = tag_names[i];
    let ke = _validate_tag_name(k);
    if ke.len() > 0 {
      return ke;
    }
    i = i + 1;
  }
  if prefix.len() > 0 {
    let pe = _validate_prefix(prefix);
    if pe.len() > 0 {
      return pe;
    }
  }
  let ce = _validate_command(command);
  if ce.len() > 0 {
    return ce;
  }
  var j = 0;
  while j < params.len() {
    let p: Str = params[j];
    let pae = _validate_param(p);
    if pae.len() > 0 {
      return pae;
    }
    j = j + 1;
  }
  if has_trailing {
    let te = _validate_trailing(trailing);
    if te.len() > 0 {
      return te;
    }
  }
  return "";
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

// Append the wire form of `m` (tags, prefix, command, params, trailing) plus
// the terminating CRLF to `out`. The message must satisfy the IrcMessage
// invariants; both irc_parse and the build functions maintain them.
fn _push_message(out: &mut Vec[UInt8], m: &IrcMessage) {
  if m.tag_names.len() > 0 {
    out.push(_IRC_AT);
    var t = 0;
    while t < m.tag_names.len() {
      if t > 0 {
        out.push(_IRC_SEMI);
      }
      let k: Str = m.tag_names[t];
      builder.sb_push_str(out, k);
      let f: Int = m.tag_flags[t];
      if f == 1 {
        out.push(_IRC_EQ);
        let v: Str = m.tag_values[t];
        _push_tag_value(out, v);
      }
      t = t + 1;
    }
    out.push(_IRC_SPACE);
  }
  if m.has_prefix {
    out.push(_IRC_COLON);
    let p: Str = m.prefix;
    builder.sb_push_str(out, p);
    out.push(_IRC_SPACE);
  }
  let c: Str = m.command;
  builder.sb_push_str(out, c);
  var j = 0;
  while j < m.params.len() {
    out.push(_IRC_SPACE);
    let pv: Str = m.params[j];
    builder.sb_push_str(out, pv);
    j = j + 1;
  }
  if m.has_trailing {
    out.push(_IRC_SPACE);
    out.push(_IRC_COLON);
    let tv: Str = m.trailing;
    builder.sb_push_str(out, tv);
  }
  out.push(_IRC_CR);
  out.push(_IRC_LF);
}

// ---------------------------------------------------------------------------
// Public API -- parsing
// ---------------------------------------------------------------------------

/// Parse one IRC message line.
/// Params: text - one message, with or without a trailing CRLF/LF/CR.
/// Grammar: [ '@' tags SP ] [ ':' prefix SP ] command [ SP middle ]* [ SP ':'
/// trailing ]; the exact statement is in SPEC.md. The input is truncated at
/// the first CR or LF, so anything after the line terminator is ignored;
/// leading spaces before the tags/prefix/command are skipped; middle
/// parameters are separated by one or more spaces; the first parameter byte
/// ':' starts the trailing text and the rest of the line is its value.
/// Returns: Ok(IrcMessage) with the tags decoded, the prefix split into
/// nick/user/host, the command verbatim, the middle parameters in `params`
/// and the trailing text in `trailing` (`has_trailing` distinguishes "CMD :"
/// from "CMD").
/// Error case: Err("irc: empty message") when the line has no
/// non-space byte; Err("irc: empty tags") when a tag section holds no tag;
/// Err("irc: empty prefix") for a ':' with nothing before the next space;
/// Err("irc: missing command") when no command follows the tags/prefix.
/// Complexity: O(len(text)).
pub fn irc_parse(text: Str) -> Result[IrcMessage, Str] {
  var m = IrcMessage{
    tag_names: Vec[Str].new();
    tag_values: Vec[Str].new();
    tag_flags: Vec[Int].new();
    has_prefix: false;
    prefix: "";
    nick: "";
    user: "";
    host: "";
    is_server_prefix: false;
    command: "";
    params: Vec[Str].new();
    has_trailing: false;
    trailing: "";
  };
  let n = _line_end(text);
  if _only_spaces(text, 0, n) {
    return _err_msg("irc: empty message");
  }
  var i = 0;
  while i < n && string.byte_at(text, i) == _IRC_SPACE {
    i = i + 1;
  }
  if string.byte_at(text, i) == _IRC_AT {
    let sp = _find_byte(text, i + 1, n, _IRC_SPACE);
    if sp < 0 {
      return _err_msg("irc: missing command");
    }
    let terr = _parse_tag_section(text, i + 1, sp, &mut m);
    if terr.len() > 0 {
      return _err_msg(terr);
    }
    i = sp;
  }
  while i < n && string.byte_at(text, i) == _IRC_SPACE {
    i = i + 1;
  }
  if i >= n {
    return _err_msg("irc: missing command");
  }
  if string.byte_at(text, i) == _IRC_COLON {
    let sp = _find_byte(text, i + 1, n, _IRC_SPACE);
    var pend = n;
    if sp >= 0 {
      pend = sp;
    }
    let praw = string.str_slice(text, i + 1, pend);
    if praw.len() == 0 {
      return _err_msg("irc: empty prefix");
    }
    let p = irc_parse_prefix(praw);
    m.has_prefix = true;
    m.prefix = praw;
    m.nick = p.nick;
    m.user = p.user;
    m.host = p.host;
    m.is_server_prefix = p.is_server;
    i = pend;
    while i < n && string.byte_at(text, i) == _IRC_SPACE {
      i = i + 1;
    }
    if i >= n {
      return _err_msg("irc: missing command");
    }
  }
  let cstart = i;
  while i < n && string.byte_at(text, i) != _IRC_SPACE {
    i = i + 1;
  }
  m.command = string.str_slice(text, cstart, i);
  while i < n {
    while i < n && string.byte_at(text, i) == _IRC_SPACE {
      i = i + 1;
    }
    if i >= n {
      break;
    }
    if string.byte_at(text, i) == _IRC_COLON {
      m.has_trailing = true;
      m.trailing = string.str_slice(text, i + 1, n);
      break;
    }
    let ps = i;
    while i < n && string.byte_at(text, i) != _IRC_SPACE {
      i = i + 1;
    }
    m.params.push(string.str_slice(text, ps, i));
  }
  return _ok_msg(m);
}

/// Split one IRC prefix into its parts.
/// Params: prefix - "nick!user@host", "nick!user", "nick@host", "nick" or a
/// server name; a leading ':' is accepted and stripped.
/// Grammar: the first '@' separates the host, the first '!' before it
/// separates the user; '!' or '@' after the host separator stay in the host.
/// Returns: IrcPrefix with `raw` (no leading ':'), the three parts (empty
/// when absent), and `is_server` true only when the text carries neither
/// '!' nor '@' (then `nick` holds the whole text). An empty prefix yields
/// all-empty parts and `is_server == false`.
/// Error case: none.
/// Complexity: O(len(prefix)).
pub fn irc_parse_prefix(prefix: Str) -> IrcPrefix {
  var raw = prefix;
  if raw.len() > 0 && string.byte_at(raw, 0) == _IRC_COLON {
    raw = string.str_slice(raw, 1, raw.len());
  }
  let n = raw.len();
  if n == 0 {
    return IrcPrefix{ raw: ""; nick: ""; user: ""; host: ""; is_server: false; };
  }
  var bang = -1;
  var at = -1;
  var i = 0;
  while i < n {
    let b = string.byte_at(raw, i);
    if b == _IRC_BANG && bang < 0 {
      bang = i;
    }
    if b == _IRC_AT && at < 0 {
      at = i;
    }
    i = i + 1;
  }
  var nick = "";
  var user = "";
  var host = "";
  var is_server = false;
  if bang < 0 && at < 0 {
    nick = raw;
    is_server = true;
  } elif bang >= 0 && (at < 0 || bang < at) {
    nick = string.str_slice(raw, 0, bang);
    if at >= 0 {
      user = string.str_slice(raw, bang + 1, at);
      host = string.str_slice(raw, at + 1, n);
    } else {
      user = string.str_slice(raw, bang + 1, n);
    }
  } else {
    nick = string.str_slice(raw, 0, at);
    host = string.str_slice(raw, at + 1, n);
  }
  return IrcPrefix{ raw: raw; nick: nick; user: user; host: host; is_server: is_server; };
}

/// Render one IrcMessage back to wire text.
/// Params: m - a message produced by irc_parse or the build functions.
/// Returns: the tags (decoded values re-escaped), the prefix, the command,
/// the middle parameters and the trailing text joined by single spaces, with
/// a terminating CRLF. A valueless tag renders as its bare name and a tag
/// with an explicit empty value keeps its '=' (parse/render round-trips are
/// byte-exact for well-formed input); a trailing text that is present but
/// empty renders as a bare ':'.
/// Error case: none (the IrcMessage invariants are maintained by the
/// constructors in this module).
/// Complexity: O(total length).
pub fn irc_render(m: &IrcMessage) -> Str {
  var out = Vec[UInt8].new();
  _push_message(&mut out, m);
  return builder.sb_to_str(&out);
}

// ---------------------------------------------------------------------------
// Public API -- building
// ---------------------------------------------------------------------------

/// Build one IRC message line without tags and without a prefix.
/// Params: command - ASCII letters/digits only; params - the middle
/// parameters in order; trailing - the trailing text (spaces and ':' are
/// legal); has_trailing - true to emit " :<trailing>" even when empty.
/// Returns: Ok(line) in wire form with a terminating CRLF, e.g.
/// irc_build("PRIVMSG", ["#chan"], "hello", true) ->
/// "PRIVMSG #chan :hello\r\n".
/// Error case: Err("irc: empty command");
/// Err("irc: invalid command: <command>") for a non-alphanumeric byte;
/// Err("irc: empty parameter"); Err("irc: invalid parameter: <param>") for a
/// space, CR, LF or a leading ':' in a middle parameter;
/// Err("irc: trailing contains a line break") for CR/LF in the trailing.
/// Complexity: O(total length).
pub fn irc_build(command: Str, params: Vec[Str], trailing: Str, has_trailing: Bool) -> Result[Str, Str] {
  var no_tags = Vec[Str].new();
  var no_values = Vec[Str].new();
  return irc_build_full(no_tags, no_values, "", command, params, trailing, has_trailing);
}

/// Build one IRC message line with tags and an optional prefix.
/// Params: tag_names - tag keys in wire order; tag_values - values,
/// index-aligned with tag_names; a value that is empty renders as a
/// valueless tag (the specs treat the two forms as equivalent); prefix - the
/// prefix text without ':', or "" for none; command/params/trailing/
/// has_trailing - as in irc_build.
/// Returns: Ok(line) in wire form with a terminating CRLF. Tag values may
/// contain any byte; ';', space, '\', CR and LF are escaped.
/// Error case: Err("irc: tag name/value count mismatch");
/// Err("irc: empty tag name"); Err("irc: invalid tag name: <name>") for a
/// space, ';', '=' or CR/LF in a tag name;
/// Err("irc: invalid prefix: <prefix>") for a space or CR/LF;
/// plus every error of irc_build.
/// Complexity: O(total length).
pub fn irc_build_full(tag_names: Vec[Str], tag_values: Vec[Str], prefix: Str, command: Str, params: Vec[Str], trailing: Str, has_trailing: Bool) -> Result[Str, Str] {
  let verr = _validate_build(&tag_names, &tag_values, prefix, command, &params, trailing, has_trailing);
  if verr.len() > 0 {
    return _err_str(verr);
  }
  var flags = Vec[Int].new();
  var i = 0;
  while i < tag_values.len() {
    let v: Str = tag_values[i];
    if v.len() > 0 {
      flags.push(1);
    } else {
      flags.push(0);
    }
    i = i + 1;
  }
  var has_prefix = prefix.len() > 0;
  var m = IrcMessage{
    tag_names: tag_names;
    tag_values: tag_values;
    tag_flags: flags;
    has_prefix: has_prefix;
    prefix: prefix;
    nick: "";
    user: "";
    host: "";
    is_server_prefix: false;
    command: command;
    params: params;
    has_trailing: has_trailing;
    trailing: trailing;
  };
  var out = Vec[UInt8].new();
  _push_message(&mut out, &m);
  return _ok_str(builder.sb_to_str(&out));
}

/// Build one numeric reply line, e.g. ":irc.example.net 001 nick :Welcome".
/// Params: prefix - the server prefix without ':', or "" for none; code -
/// the numeric code, 0..999 (formatted with leading zeros to three digits);
/// params/trailing/has_trailing - as in irc_build.
/// Returns: Ok(line) in wire form with a terminating CRLF.
/// Error case: Err("irc: invalid numeric code: <code>") when code is
/// negative or greater than 999; plus every error of irc_build_full.
/// Complexity: O(total length).
pub fn irc_build_numeric(prefix: Str, code: Int, params: Vec[Str], trailing: Str, has_trailing: Bool) -> Result[Str, Str] {
  if code < 0 || code > 999 {
    return _err_str("irc: invalid numeric code: " + _int_str(code));
  }
  let cmd = _num3(code);
  var no_tags = Vec[Str].new();
  var no_values = Vec[Str].new();
  return irc_build_full(no_tags, no_values, prefix, cmd, params, trailing, has_trailing);
}

// ---------------------------------------------------------------------------
// Public API -- numeric replies
// ---------------------------------------------------------------------------

/// True when the message command is exactly three ASCII digits.
/// Params: m - the parsed message.
/// Returns: true for a numeric reply code ("001", "433", ...), false
/// otherwise (wrong length or a non-digit byte).
/// Error case: none.
/// Complexity: O(1).
pub fn irc_is_numeric(m: &IrcMessage) -> Bool {
  let c: Str = m.command;
  if c.len() != 3 {
    return false;
  }
  var i = 0;
  while i < 3 {
    let b = (string.byte_at(c, i) as Int) & 0xFF;
    if b < 48 || b > 57 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// The numeric code of a numeric reply ("001" -> 1, "433" -> 433).
/// Params: m - the parsed message.
/// Returns: Ok(code) with code in 0..999; leading zeros are accepted.
/// Error case: Err("irc: not a numeric reply") when the command is not
/// exactly three ASCII digits.
/// Complexity: O(1).
pub fn irc_numeric_code(m: &IrcMessage) -> Result[Int, Str] {
  if !irc_is_numeric(m) {
    return _err_int("irc: not a numeric reply");
  }
  let c: Str = m.command;
  let h = ((string.byte_at(c, 0) as Int) & 0xFF) - 48;
  let t = ((string.byte_at(c, 1) as Int) & 0xFF) - 48;
  let u = ((string.byte_at(c, 2) as Int) & 0xFF) - 48;
  return _ok_int(h * 100 + t * 10 + u);
}

// ---------------------------------------------------------------------------
// Public API -- command comparison and field access
// ---------------------------------------------------------------------------

/// ASCII case-insensitive string equality.
/// Params: a, b - the texts to compare.
/// Returns: true when both have the same length and every pair of bytes is
/// equal after mapping 'a'..'z' to 'A'..'Z'; all other bytes compare
/// exactly. This is the comparison used for commands: it operates on
/// integers after the byte reads, never on Str values from a Vec.
/// Error case: none.
/// Complexity: O(min(len(a), len(b))).
pub fn irc_eq_ci(a: Str, b: Str) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x = (string.byte_at(a, i) as Int) & 0xFF;
    let y = (string.byte_at(b, i) as Int) & 0xFF;
    if _upper_byte(x) != _upper_byte(y) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Case-insensitive comparison of the message command with `want`, e.g.
/// irc_command_is(&m, "privmsg") is true for "PRIVMSG".
/// Params: m - the parsed message; want - the command text to test.
/// Returns: irc_eq_ci(m.command, want).
/// Error case: none.
/// Complexity: O(len(command)).
pub fn irc_command_is(m: &IrcMessage, want: Str) -> Bool {
  let c: Str = m.command;
  return irc_eq_ci(c, want);
}

/// True when the message carries at least one tag.
/// Params: m - the parsed message.
/// Returns: m.tag_names.len() > 0.
/// Error case: none.
/// Complexity: O(1).
pub fn irc_has_tags(m: &IrcMessage) -> Bool {
  return m.tag_names.len() > 0;
}

/// Number of tags on the message.
/// Params: m - the parsed message.
/// Returns: the tag count (duplicates counted).
/// Error case: none.
/// Complexity: O(1).
pub fn irc_tag_count(m: &IrcMessage) -> Int {
  return m.tag_names.len();
}

/// Name of tag `i`, in wire order.
/// Params: m - the parsed message; i - zero-based tag index.
/// Returns: the tag name verbatim (case-sensitive); "" when i is negative or
/// past the last tag.
/// Error case: none.
/// Complexity: O(1).
pub fn irc_tag_name(m: &IrcMessage, i: Int) -> Str {
  if i < 0 || i >= m.tag_names.len() {
    return "";
  }
  let v: Str = m.tag_names[i];
  return v;
}

/// Decoded value of tag `i`.
/// Params: m - the parsed message; i - zero-based tag index.
/// Returns: the decoded value ("" for a valueless tag and for an explicit
/// empty value); "" when i is negative or past the last tag.
/// Error case: none.
/// Complexity: O(1).
pub fn irc_tag_value(m: &IrcMessage, i: Int) -> Str {
  if i < 0 || i >= m.tag_values.len() {
    return "";
  }
  let v: Str = m.tag_values[i];
  return v;
}

/// True when tag `i` was written with an explicit "=value" (even when that
/// value is empty).
/// Params: m - the parsed message; i - zero-based tag index.
/// Returns: true for "key=value" / "key=", false for a bare "key" and for an
/// out-of-range index.
/// Error case: none.
/// Complexity: O(1).
pub fn irc_tag_has_value(m: &IrcMessage, i: Int) -> Bool {
  if i < 0 || i >= m.tag_flags.len() {
    return false;
  }
  let f: Int = m.tag_flags[i];
  return f == 1;
}

/// Value of the tag named `name`, searching from the end.
/// Params: m - the parsed message; name - the tag name, matched byte-exactly
/// (tag names are case-sensitive opaque identifiers).
/// Returns: Some(value) for the final occurrence of `name` (the specs say
/// all but the last duplicate should be disregarded), where a valueless tag
/// yields Some(""); None when the tag is absent.
/// Error case: none.
/// Complexity: O(tag count).
pub fn irc_tag(m: &IrcMessage, name: Str) -> Option[Str] {
  let i = _tag_last_index(m, name);
  if i < 0 {
    return None;
  }
  let v: Str = m.tag_values[i];
  return Some(v);
}

/// Number of middle parameters (the trailing text is not counted).
/// Params: m - the parsed message.
/// Returns: m.params.len().
/// Error case: none.
/// Complexity: O(1).
pub fn irc_param_count(m: &IrcMessage) -> Int {
  return m.params.len();
}

/// Middle parameter `i`, in wire order.
/// Params: m - the parsed message; i - zero-based parameter index.
/// Returns: the parameter text; "" when i is negative or past the last
/// middle parameter (the trailing text is not reachable here).
/// Error case: none.
/// Complexity: O(1).
pub fn irc_param(m: &IrcMessage, i: Int) -> Str {
  if i < 0 || i >= m.params.len() {
    return "";
  }
  let v: Str = m.params[i];
  return v;
}
