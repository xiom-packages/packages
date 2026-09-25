// XIOM -- xiom.ass: a strict, in-memory ASS/SSA subtitle codec for a
// documented subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (SPEC.md states the exact grammar, policies and error catalog):
//   * sections `[Script Info]` (key: value lines preserved), `[V4+ Styles]`
//     and `[V4 Styles]` (a `Format:` declaration followed by `Style:` field
//     rows), `[Events]` (`Format:` followed by `Dialogue:`/`Comment:` rows),
//     and any other section preserved raw line by line;
//   * the `[Events]` Format declaration defines the field mapping; when it is
//     absent the documented default mapping (Layer, Start, End, Style, Name,
//     MarginL, MarginR, MarginV, Effect, Text) applies. A `Dialogue:` or
//     `Comment:` row before its section's Format line is an error;
//   * timestamps are `h:mm:ss.cc` centiseconds: exactly one hour digit and
//     two digits for minutes, seconds and centiseconds. The canonical
//     emitter prints hours without padding (one digit below 10);
//   * the last declared field of a `Style:`/`Dialogue:`/`Comment:` row is
//     captured raw to the end of the line, so commas inside Text are
//     preserved; the other fields are trimmed of spaces/tabs. `\N`, `\n` and
//     `{...}` override blocks inside Text are raw bytes;
//   * storage is flat: parallel Vecs plus byte ranges (section ranges,
//     per-section Format field ranges, row field spans). There is no
//     Vec[StructType] and no rendering, override-tag interpretation or font
//     attachment parsing;
//   * the canonical emitter writes sections in the documented kind order
//     (Script Info, styles, Events, other), normalizes CRLF to LF and
//     renumbers nothing (unlike xiom.srt): every stored raw line is written
//     back verbatim.
//
// v0.61.3 notes that shaped this module (SPEC.md section 12):
//   * free functions only; no methods, lambdas or match;
//   * Ok/Err are constructed only in the tiny leaf helpers below;
//   * Str values read from Vec[Str] are compared through
//     xiom.string.compare.str_compare, never `==` (BUG 17);
//   * every byte is widened with `(string.byte_at(s, pos) as Int) & 0xFF`;
//   * internal parsers return "" on success or an "ass: ..." message; the
//     leaf helpers turn that message into Err.

module xiom.ass

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// A parsed ASS/SSA document, stored flat.
/// Sections appear in document order: `section_names[i]` (trimmed text
/// between the brackets), `section_kinds[i]` (0 = Script Info, 1 = V4/V4+
/// styles, 2 = Events, 3 = other) and the raw line range
/// `section_lines[section_starts[i] .. section_ends[i])`. Every line of every
/// section is preserved verbatim except the section header itself.
/// `section_fmt_starts[i]`/`section_fmt_ends[i]` give the range of declared
/// Format field names for section `i` in the shared `format_fields` pool, or
/// -1/-1 when the section has none. `info_keys`/`info_values` hold Script Info
/// key: value pairs. `style_sections[i]` is the owning section index of style
/// row `i`, whose field values are `style_fields[style_starts[i] ..
/// style_ends[i])`. `event_kinds[i]` is 0 for Dialogue and 1 for Comment;
/// `event_sections[i]` is the owning section; `event_starts[i]`/`event_ends[i]`
/// are the parsed Start/End values in centiseconds (-1 when the section's
/// Format has no such field); the field values are
/// `event_fields[event_fstarts[i] .. event_fends[i])`.
pub type Ass = {
  section_names: Vec[Str];
  section_kinds: Vec[Int];
  section_starts: Vec[Int];
  section_ends: Vec[Int];
  section_lines: Vec[Str];
  section_fmt_starts: Vec[Int];
  section_fmt_ends: Vec[Int];
  format_fields: Vec[Str];
  info_keys: Vec[Str];
  info_values: Vec[Str];
  style_sections: Vec[Int];
  style_starts: Vec[Int];
  style_ends: Vec[Int];
  style_fields: Vec[Str];
  event_kinds: Vec[Int];
  event_sections: Vec[Int];
  event_starts: Vec[Int];
  event_ends: Vec[Int];
  event_fstarts: Vec[Int];
  event_fends: Vec[Int];
  event_fields: Vec[Str];
}

// --------------------------------------------------
//  Byte constants (Int, see the header note)
// --------------------------------------------------

const _TAB: Int = 9;
const _LF: Int = 10;
const _CR: Int = 13;
const _SPACE: Int = 32;
const _COMMA: Int = 44;
const _DOT: Int = 46;
const _COLON: Int = 58;
const _SEMI: Int = 59;
const _ZERO: Int = 48;
const _NINE: Int = 57;
const _LBRACKET: Int = 91;
const _RBRACKET: Int = 93;
const _DEL: Int = 127;
const _C0_LIMIT: Int = 32;

// --------------------------------------------------
//  Result constructors (leaf helpers)
// --------------------------------------------------

// Ok(v) for Result[Ass, Str].
fn _ok_ass(v: Ass) -> Result[Ass, Str] {
  return Ok(v);
}

// Err(m) for Result[Ass, Str].
fn _err_ass(m: Str) -> Result[Ass, Str] {
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

// --------------------------------------------------
//  Internal text helpers
// --------------------------------------------------

// Byte `pos` of `s` as an Int (0..255). Callers guarantee the bounds. The
// mask keeps every widened byte non-negative (see the header note).
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// Split `text` into lines on LF. A CR immediately before LF is dropped, so
// CRLF documents produce the same lines as LF documents. A trailing LF does
// not produce a final empty line.
fn _split_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var start = 0;
  var i = 0;
  while i < len {
    if _byte(text, i) == _LF {
      var end = i;
      if end > start && _byte(text, end - 1) == _CR { end = end - 1; }
      out.push(string.str_slice(text, start, end));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < len {
    var end = len;
    if end > start && _byte(text, end - 1) == _CR { end = end - 1; }
    out.push(string.str_slice(text, start, end));
  }
  return out;
}

// Position of the first byte at or after `from` that is not a space or tab.
fn _skip_ws(s: Str, from: Int) -> Int {
  let len = s.len();
  var a = from;
  var go = true;
  while a < len && go {
    let c = _byte(s, a);
    if c == _SPACE || c == _TAB { a = a + 1; } else { go = false; }
  }
  return a;
}

// Slice [from, to) with surrounding spaces/tabs removed.
fn _trim_range(s: Str, from: Int, to: Int) -> Str {
  let a = _skip_ws(s, from);
  var b = to;
  var go = true;
  while b > a && go {
    let c = _byte(s, b - 1);
    if c == _SPACE || c == _TAB { b = b - 1; } else { go = false; }
  }
  if a > b { return ""; }
  return string.str_slice(s, a, b);
}

// Trim [from, end of string] on a Str that may have been read from a
// Vec[Str] element (see the header note).
fn _trim_from(s: Str, from: Int) -> Str {
  return _trim_range(s, from, s.len());
}

// True when `s` is a zero-byte line. Str equality goes through str_compare
// (BUG 17).
fn _is_blank(s: Str) -> Bool {
  return compare.str_compare(s, "") == 0;
}

// True when `s` begins with the exact byte sequence `prefix`.
fn _starts_with(s: Str, prefix: Str) -> Bool {
  let n = prefix.len();
  if s.len() < n { return false; }
  var i = 0;
  while i < n {
    if _byte(s, i) != _byte(prefix, i) { return false; }
    i = i + 1;
  }
  return true;
}

// Index of the first byte equal to `ch` at or after `from`, or -1.
fn _find_byte(s: Str, from: Int, ch: Int) -> Int {
  let len = s.len();
  var i = from;
  if i < 0 { i = 0; }
  while i < len {
    if _byte(s, i) == ch { return i; }
    i = i + 1;
  }
  return -1;
}

// True when `text` contains a rejected control byte: any C0 byte other than
// TAB, LF and CR, or DEL (0x7F). UTF-8 bytes >= 0x80 are not control bytes.
fn _has_control(text: Str) -> Bool {
  let n = text.len();
  var i = 0;
  while i < n {
    let c = _byte(text, i);
    if c < _C0_LIMIT {
      if c != _TAB && c != _LF && c != _CR { return true; }
    } elif c == _DEL {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Value of two ASCII digits at `pos`, or -1 when either byte is not a digit.
fn _two_digits(s: Str, pos: Int) -> Int {
  let a = _byte(s, pos);
  let b = _byte(s, pos + 1);
  if a < _ZERO || a > _NINE { return -1; }
  if b < _ZERO || b > _NINE { return -1; }
  return (a - _ZERO) * 10 + (b - _ZERO);
}

// Parse an ASS timestamp to centiseconds.
// The form is exactly "h:mm:ss.cc": one hour digit (0..9), a colon, two
// minute digits, a colon, two second digits, a dot, two centisecond digits.
// Returns the centisecond value (>= 0), -1 for a bad shape (including two
// hour digits), or -2 when minutes or seconds exceed 59.
fn _timestamp_cs(t: Str) -> Int {
  if t.len() != 10 { return -1; }
  if _byte(t, 1) != _COLON { return -1; }
  if _byte(t, 4) != _COLON { return -1; }
  if _byte(t, 7) != _DOT { return -1; }
  let h = _byte(t, 0);
  if h < _ZERO || h > _NINE { return -1; }
  let mm = _two_digits(t, 2);
  let ss = _two_digits(t, 5);
  let cc = _two_digits(t, 8);
  if mm < 0 || ss < 0 || cc < 0 { return -1; }
  if mm > 59 || ss > 59 { return -2; }
  return (h - _ZERO) * 360000 + mm * 6000 + ss * 100 + cc;
}

// Decimal formatting for non-negative values; local so the module needs no
// conversion imports.
fn _int_str(n: Int) -> Str {
  if n <= 0 { return "0"; }
  var digits = Vec[Int].new();
  var x = n;
  while x > 0 {
    let d: Int = x % 10;
    digits.push(d);
    x = x / 10;
  }
  var out = "";
  var i = digits.len() - 1;
  while i >= 0 {
    let d: Int = digits[i];
    out = out + string.str_slice("0123456789", d, d + 1);
    i = i - 1;
  }
  return out;
}

// Zero-padded to at least two digits.
fn _pad2(n: Int) -> Str {
  let s = _int_str(n);
  if n < 10 { return "0" + s; }
  return s;
}

// Canonical ASS timestamp text: hour with no leading zero (a single digit
// below 10, more digits above), minutes/seconds/centiseconds zero-padded to
// two digits. Negative values clamp to zero.
fn _fmt_timestamp(cs: Int) -> Str {
  var t = cs;
  if t < 0 { t = 0; }
  let h = t / 360000;
  let mm = (t / 6000) % 60;
  let ss = (t / 100) % 60;
  let cc = t % 100;
  var out = _int_str(h);
  out = out + ":";
  out = out + _pad2(mm);
  out = out + ":";
  out = out + _pad2(ss);
  out = out + ".";
  out = out + _pad2(cc);
  return out;
}

// Smallest of two Ints.
fn _min2(a: Int, b: Int) -> Int {
  if a < b { return a; }
  return b;
}

// Split `value` into exactly `want` fields on commas: fields 0 .. want-2 are
// trimmed of spaces/tabs and field want-1 is the raw remainder (commas
// inside it are preserved). Returns 0 on success or -1 when the value holds
// fewer than want-1 commas.
fn _split_fields(value: Str, want: Int, out: &mut Vec[Str]) -> Int {
  if want < 1 { return -1; }
  let len = value.len();
  var pos = 0;
  var j = 0;
  while j + 1 < want {
    let c = _find_byte(value, pos, _COMMA);
    if c < 0 { return -1; }
    out.push(_trim_range(value, pos, c));
    pos = c + 1;
    j = j + 1;
  }
  out.push(string.str_slice(value, pos, len));
  return 0;
}

// Append the comma-separated field names of a `Format:` declaration (the
// text after "Format:") to `fields`. Returns the number of names appended
// (>= 1), or -1 when the declaration is empty or holds an empty name.
fn _append_format(decl: Str, fields: &mut Vec[Str]) -> Int {
  let len = decl.len();
  if len == 0 { return -1; }
  var pos = 0;
  var count = 0;
  var go = true;
  while go {
    let c = _find_byte(decl, pos, _COMMA);
    var end = len;
    if c >= 0 { end = c; }
    let name = _trim_range(decl, pos, end);
    if name.len() == 0 { return -1; }
    fields.push(name);
    count = count + 1;
    if c < 0 { go = false; } else { pos = c + 1; }
  }
  return count;
}

// Append the documented default `[Events]` mapping and return its size.
fn _append_default_event_format(fields: &mut Vec[Str]) -> Int {
  fields.push("Layer");
  fields.push("Start");
  fields.push("End");
  fields.push("Style");
  fields.push("Name");
  fields.push("MarginL");
  fields.push("MarginR");
  fields.push("MarginV");
  fields.push("Effect");
  fields.push("Text");
  return 10;
}

// Index of the first `Format:` line in raw[from, to), or -1.
fn _find_format_line(raw: &Vec[Str], from: Int, to: Int) -> Int {
  var hi = to;
  if hi > raw.len() { hi = raw.len(); }
  var i = from;
  var hit = -1;
  while i < hi && hit < 0 {
    let line: Str = raw[i];
    if _starts_with(line, "Format:") { hit = i; }
    i = i + 1;
  }
  return hit;
}

// True when the line is a `Format:` declaration.
fn _is_format_line(line: Str) -> Bool {
  return _starts_with(line, "Format:");
}

// Section kind of a trimmed section name: 0 Script Info, 1 V4/V4+ styles,
// 2 Events, 3 anything else. Names are case-sensitive.
fn _classify(name: Str) -> Int {
  if compare.str_compare(name, "Script Info") == 0 { return 0; }
  if compare.str_compare(name, "V4+ Styles") == 0 { return 1; }
  if compare.str_compare(name, "V4 Styles") == 0 { return 1; }
  if compare.str_compare(name, "Events") == 0 { return 2; }
  return 3;
}

// Index of the first field in fields[from, to) whose name equals `name`, or
// -1 (first-match policy).
fn _find_field(fields: &Vec[Str], from: Int, to: Int, name: Str) -> Int {
  var lo = from;
  if lo < 0 { lo = 0; }
  var hi = to;
  if hi > fields.len() { hi = fields.len(); }
  var i = lo;
  var hit = -1;
  while i < hi && hit < 0 {
    let f: Str = fields[i];
    if compare.str_compare(f, name) == 0 { hit = i; }
    i = i + 1;
  }
  return hit;
}

// --------------------------------------------------
//  Section collection (pass 1)
// --------------------------------------------------

// Split `lines` into sections. Header lines begin with "[" and must hold a
// non-empty name closed by "]" with only spaces/tabs after it. Every other
// line inside a section is appended to `raw` verbatim; blank lines before
// the first section are ignored and non-blank text before it is an error.
// Returns "" on success or an "ass: ..." message.
fn _collect_sections(lines: &Vec[Str],
                     names: &mut Vec[Str],
                     kinds: &mut Vec[Int],
                     starts: &mut Vec[Int],
                     ends: &mut Vec[Int],
                     raw: &mut Vec[Str]) -> Str {
  let n = lines.len();
  var i = 0;
  var open = -1;
  while i < n {
    let line: Str = lines[i];
    let llen = line.len();
    if llen > 0 && _byte(line, 0) == _LBRACKET {
      if open >= 0 { ends.push(raw.len()); }
      if llen < 2 { return "ass: unterminated section name"; }
      var close = -1;
      var j = 1;
      while j < llen && close < 0 {
        if _byte(line, j) == _RBRACKET { close = j; }
        j = j + 1;
      }
      if close < 0 { return "ass: unterminated section name"; }
      let name = _trim_range(line, 1, close);
      if name.len() == 0 { return "ass: bad section name"; }
      var t = close + 1;
      while t < llen {
        let c = _byte(line, t);
        if c != _SPACE && c != _TAB { return "ass: bad section name"; }
        t = t + 1;
      }
      names.push(name);
      kinds.push(_classify(name));
      starts.push(raw.len());
      open = names.len() - 1;
    } else {
      if open < 0 {
        if !_is_blank(line) { return "ass: text before first section"; }
      } else {
        raw.push(line);
      }
    }
    i = i + 1;
  }
  if open >= 0 { ends.push(raw.len()); }
  return "";
}

// --------------------------------------------------
//  Per-section record parsing (pass 2)
// --------------------------------------------------

// Parse a Script Info section: non-blank lines that do not start with ";"
// (at byte 0) must hold `key: value`; key and value are trimmed and appended
// to the pools. Returns "" on success.
fn _parse_info_section(raw: &mut Vec[Str], ls: Int, le: Int,
                       keys: &mut Vec[Str], values: &mut Vec[Str]) -> Str {
  var k = ls;
  while k < le {
    let line: Str = raw[k];
    if !_is_blank(line) {
      let c0 = _byte(line, 0);
      if c0 != _SEMI {
        let colon = _find_byte(line, 0, _COLON);
        if colon < 0 { return "ass: bad script info line"; }
        let key = _trim_range(line, 0, colon);
        if key.len() == 0 { return "ass: bad script info line"; }
        keys.push(key);
        values.push(_trim_from(line, colon + 1));
      }
    }
    k = k + 1;
  }
  return "";
}

// Parse a styles section. The section's first `Format:` line, when present,
// declares the field names; `Style:` rows before it (or with no Format line
// at all) are "ass: style before Format", a second Format line is
// "ass: bad Format" and any other non-blank line is "ass: unexpected line".
// Returns "" on success.
fn _parse_style_section(raw: &mut Vec[Str], ls: Int, le: Int, sec: Int,
                        format_fields: &mut Vec[Str],
                        fmt_starts: &mut Vec[Int],
                        fmt_ends: &mut Vec[Int],
                        style_sections: &mut Vec[Int],
                        style_starts: &mut Vec[Int],
                        style_ends: &mut Vec[Int],
                        style_fields: &mut Vec[Str]) -> Str {
  let fmt_idx = _find_format_line(raw, ls, le);
  var fmt_count = 0;
  if fmt_idx >= 0 {
    let fline: Str = raw[fmt_idx];
    let decl = string.str_slice(fline, 7, fline.len());
    let base = format_fields.len();
    let fc = _append_format(decl, format_fields);
    if fc < 0 { return "ass: bad Format"; }
    fmt_count = fc;
    fmt_starts.push(base);
    fmt_ends.push(format_fields.len());
  } else {
    fmt_starts.push(-1);
    fmt_ends.push(-1);
  }
  var k = ls;
  while k < le {
    let line: Str = raw[k];
    if _is_blank(line) {
    } elif k == fmt_idx {
    } elif _is_format_line(line) {
      return "ass: bad Format";
    } elif _starts_with(line, "Style:") {
      if fmt_idx < 0 || k < fmt_idx { return "ass: style before Format"; }
      let val = string.str_slice(line, 6, line.len());
      let flds = Vec[Str].new();
      let sc = _split_fields(val, fmt_count, &flds);
      if sc != 0 { return "ass: field count mismatch"; }
      style_sections.push(sec);
      style_starts.push(style_fields.len());
      var z = 0;
      while z < flds.len() {
        let v: Str = flds[z];
        style_fields.push(v);
        z = z + 1;
      }
      style_ends.push(style_fields.len());
    } else {
      return "ass: unexpected line";
    }
    k = k + 1;
  }
  return "";
}

// Parse one `Dialogue:`/`Comment:` row into the flat event record. `kind` is
// 0 for Dialogue and 1 for Comment; `fmt_base`/`fmt_count` locate the
// section's field names in `format_fields`. Returns "" on success.
fn _parse_event_row(line: Str, kind: Int, fmt_count: Int, fmt_base: Int,
                    format_fields: &Vec[Str], sec: Int,
                    event_kinds: &mut Vec[Int],
                    event_sections: &mut Vec[Int],
                    event_starts: &mut Vec[Int],
                    event_ends: &mut Vec[Int],
                    event_fstarts: &mut Vec[Int],
                    event_fends: &mut Vec[Int],
                    event_fields: &mut Vec[Str]) -> Str {
  var off = 9;
  if kind == 1 { off = 8; }
  let val = string.str_slice(line, off, line.len());
  let flds = Vec[Str].new();
  let sc = _split_fields(val, fmt_count, &flds);
  if sc != 0 { return "ass: field count mismatch"; }
  let fend = fmt_base + fmt_count;
  let so = _find_field(format_fields, fmt_base, fend, "Start");
  let eo = _find_field(format_fields, fmt_base, fend, "End");
  var scs = -1;
  var ecs = -1;
  if so >= 0 {
    let sv: Str = flds[so - fmt_base];
    let v = _timestamp_cs(sv);
    if v == -1 { return "ass: bad timestamp shape"; }
    if v == -2 { return "ass: timestamp out of range"; }
    scs = v;
  }
  if eo >= 0 {
    let ev: Str = flds[eo - fmt_base];
    let v2 = _timestamp_cs(ev);
    if v2 == -1 { return "ass: bad timestamp shape"; }
    if v2 == -2 { return "ass: timestamp out of range"; }
    ecs = v2;
  }
  event_kinds.push(kind);
  event_sections.push(sec);
  event_starts.push(scs);
  event_ends.push(ecs);
  event_fstarts.push(event_fields.len());
  var z = 0;
  while z < flds.len() {
    let v3: Str = flds[z];
    event_fields.push(v3);
    z = z + 1;
  }
  event_fends.push(event_fields.len());
  return "";
}

// Parse an Events section. When the section has no `Format:` line the
// documented default mapping is materialized; when it has one, rows before
// it are rejected ("ass: dialogue before Format" / "ass: comment before
// Format"). Returns "" on success.
fn _parse_event_section(raw: &mut Vec[Str], ls: Int, le: Int, sec: Int,
                        format_fields: &mut Vec[Str],
                        fmt_starts: &mut Vec[Int],
                        fmt_ends: &mut Vec[Int],
                        event_kinds: &mut Vec[Int],
                        event_sections: &mut Vec[Int],
                        event_starts: &mut Vec[Int],
                        event_ends: &mut Vec[Int],
                        event_fstarts: &mut Vec[Int],
                        event_fends: &mut Vec[Int],
                        event_fields: &mut Vec[Str]) -> Str {
  let fmt_idx = _find_format_line(raw, ls, le);
  var fmt_count = 0;
  var fmt_base = -1;
  if fmt_idx >= 0 {
    let fline: Str = raw[fmt_idx];
    let decl = string.str_slice(fline, 7, fline.len());
    let base = format_fields.len();
    let fc = _append_format(decl, format_fields);
    if fc < 0 { return "ass: bad Format"; }
    fmt_count = fc;
    fmt_base = base;
    fmt_starts.push(base);
    fmt_ends.push(format_fields.len());
  } else {
    let base = format_fields.len();
    fmt_count = _append_default_event_format(format_fields);
    fmt_base = base;
    fmt_starts.push(base);
    fmt_ends.push(format_fields.len());
  }
  var k = ls;
  while k < le {
    let line: Str = raw[k];
    if _is_blank(line) {
    } elif k == fmt_idx {
    } elif _is_format_line(line) {
      return "ass: bad Format";
    } elif _starts_with(line, "Dialogue:") {
      if fmt_idx >= 0 && k < fmt_idx { return "ass: dialogue before Format"; }
      let m = _parse_event_row(line, 0, fmt_count, fmt_base, format_fields,
                               sec, event_kinds, event_sections, event_starts,
                               event_ends, event_fstarts, event_fends,
                               event_fields);
      if m.len() > 0 { return m; }
    } elif _starts_with(line, "Comment:") {
      if fmt_idx >= 0 && k < fmt_idx { return "ass: comment before Format"; }
      let m2 = _parse_event_row(line, 1, fmt_count, fmt_base, format_fields,
                                sec, event_kinds, event_sections, event_starts,
                                event_ends, event_fstarts, event_fends,
                                event_fields);
      if m2.len() > 0 { return m2; }
    } else {
      return "ass: unexpected line";
    }
    k = k + 1;
  }
  return "";
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

// Whole-document parse over the already-split lines. Returns "" from every
// internal helper on success; the first "ass: ..." message is returned as
// Err through the leaf helper.
fn _ass_parse_lines(lines: &Vec[Str]) -> Result[Ass, Str] {
  var names = Vec[Str].new();
  var kinds = Vec[Int].new();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  var raw = Vec[Str].new();
  let cmsg: Str = _collect_sections(lines, &mut names, &mut kinds, &mut starts,
                                    &mut ends, &mut raw);
  if cmsg.len() > 0 { return _err_ass(cmsg); }
  if names.len() == 0 { return _err_ass("ass: empty input"); }
  var has_events = false;
  var q = 0;
  while q < kinds.len() {
    let kk: Int = kinds[q];
    if kk == 2 { has_events = true; }
    q = q + 1;
  }
  if !has_events { return _err_ass("ass: missing [Events]"); }

  var fmt_starts = Vec[Int].new();
  var fmt_ends = Vec[Int].new();
  var format_fields = Vec[Str].new();
  var info_keys = Vec[Str].new();
  var info_values = Vec[Str].new();
  var style_sections = Vec[Int].new();
  var style_starts = Vec[Int].new();
  var style_ends = Vec[Int].new();
  var style_fields = Vec[Str].new();
  var event_kinds = Vec[Int].new();
  var event_sections = Vec[Int].new();
  var event_starts = Vec[Int].new();
  var event_ends = Vec[Int].new();
  var event_fstarts = Vec[Int].new();
  var event_fends = Vec[Int].new();
  var event_fields = Vec[Str].new();

  let sec_n = names.len();
  var s = 0;
  while s < sec_n {
    let kind: Int = kinds[s];
    let ls: Int = starts[s];
    let le: Int = ends[s];
    if kind == 0 {
      let m = _parse_info_section(&mut raw, ls, le, &mut info_keys, &mut info_values);
      if m.len() > 0 { return _err_ass(m); }
      fmt_starts.push(-1);
      fmt_ends.push(-1);
    } elif kind == 1 {
      let m2 = _parse_style_section(&mut raw, ls, le, s, &mut format_fields,
                                    &mut fmt_starts, &mut fmt_ends,
                                    &mut style_sections, &mut style_starts,
                                    &mut style_ends, &mut style_fields);
      if m2.len() > 0 { return _err_ass(m2); }
    } elif kind == 2 {
      let m3 = _parse_event_section(&mut raw, ls, le, s, &mut format_fields,
                                    &mut fmt_starts, &mut fmt_ends,
                                    &mut event_kinds, &mut event_sections,
                                    &mut event_starts, &mut event_ends,
                                    &mut event_fstarts, &mut event_fends,
                                    &mut event_fields);
      if m3.len() > 0 { return _err_ass(m3); }
    } else {
      fmt_starts.push(-1);
      fmt_ends.push(-1);
    }
    s = s + 1;
  }

  let a = Ass{
    section_names: names;
    section_kinds: kinds;
    section_starts: starts;
    section_ends: ends;
    section_lines: raw;
    section_fmt_starts: fmt_starts;
    section_fmt_ends: fmt_ends;
    format_fields: format_fields;
    info_keys: info_keys;
    info_values: info_values;
    style_sections: style_sections;
    style_starts: style_starts;
    style_ends: style_ends;
    style_fields: style_fields;
    event_kinds: event_kinds;
    event_sections: event_sections;
    event_starts: event_starts;
    event_ends: event_ends;
    event_fstarts: event_fstarts;
    event_fends: event_fends;
    event_fields: event_fields;
  };
  return _ok_ass(a);
}

/// Parse an in-memory ASS/SSA document (the documented subset; see SPEC.md).
/// Accepts LF and CRLF line endings. The document must contain an `[Events]`
/// section. Sections are `[Script Info]`, `[V4+ Styles]`, `[V4 Styles]`,
/// `[Events]` and any other bare section; every non-header line is preserved
/// raw. Rows are validated against their section's `Format:` declaration (or
/// the documented default for `[Events]`), timestamps must be `h:mm:ss.cc`
/// and the last declared field of a row is captured raw to the end of the
/// line.
/// Errors: "ass: control byte", "ass: empty input",
/// "ass: text before first section", "ass: unterminated section name",
/// "ass: bad section name", "ass: missing [Events]", "ass: bad Format",
/// "ass: bad script info line", "ass: style before Format",
/// "ass: dialogue before Format", "ass: comment before Format",
/// "ass: field count mismatch", "ass: bad timestamp shape",
/// "ass: timestamp out of range", "ass: unexpected line"; see SPEC.md.
/// Complexity: O(input length).
pub fn ass_parse(text: Str) -> Result[Ass, Str] {
  if _has_control(text) { return _err_ass("ass: control byte"); }
  let lines = _split_lines(text);
  return _ass_parse_lines(&lines);
}

// --------------------------------------------------
//  Formatter
// --------------------------------------------------

/// Serialize a document as canonical ASS.
/// Sections are written in the documented kind order (Script Info, styles,
/// Events, other), preserving document order inside each kind; each header is
/// `[name]` (the stored trimmed name), each stored raw line is written
/// verbatim followed by LF, and nothing is renumbered: rows, field values,
/// timestamps and spacing keep their stored bytes. An input that already
/// uses canonical order and LF round-trips byte-exactly; CRLF and section
/// reordering are normalized. An empty document formats to "".
/// Complexity: O(section lines).
pub fn ass_format(a: &Ass) -> Str {
  let total = _section_count(a);
  let lines_total = a.section_lines.len();
  var out = "";
  var kind = 0;
  while kind < 4 {
    var i = 0;
    while i < total {
      let kk: Int = a.section_kinds[i];
      if kk == kind {
        let name: Str = a.section_names[i];
        out = out + "[";
        out = out + name;
        out = out + "]\n";
        var p0: Int = a.section_starts[i];
        var p1: Int = a.section_ends[i];
        if p0 < 0 { p0 = 0; }
        if p0 > lines_total { p0 = lines_total; }
        if p1 < p0 { p1 = p0; }
        if p1 > lines_total { p1 = lines_total; }
        var p = p0;
        while p < p1 {
          let line: Str = a.section_lines[p];
          out = out + line;
          out = out + "\n";
          p = p + 1;
        }
      }
      i = i + 1;
    }
    kind = kind + 1;
  }
  return out;
}

// --------------------------------------------------
//  Public API -- timestamps
// --------------------------------------------------

/// Parse one ASS timestamp and return whole centiseconds.
/// The form is exactly "h:mm:ss.cc": one hour digit (0..9), two-minute,
/// two-second and two-centisecond digit fields, and a dot separator. No
/// surrounding whitespace is allowed.
/// Errors: "ass: bad timestamp shape" for a malformed shape or digit count,
/// "ass: timestamp out of range" when minutes or seconds exceed 59.
pub fn ass_parse_timestamp(t: Str) -> Result[Int, Str] {
  let v = _timestamp_cs(t);
  if v == -1 { return _err_int("ass: bad timestamp shape"); }
  if v == -2 { return _err_int("ass: timestamp out of range"); }
  return _ok_int(v);
}

/// Canonical ASS timestamp text "h:mm:ss.cc" for `cs` (the reverse of
/// `ass_parse_timestamp`). Negative values clamp to zero. Hours print with a
/// single digit below 10 and with more digits above (such values do not
/// re-parse; see SPEC.md).
pub fn ass_format_timestamp(cs: Int) -> Str {
  return _fmt_timestamp(cs);
}

// --------------------------------------------------
//  Public API -- counts
// --------------------------------------------------

// Section count: the minimum length of the section vectors, so a hand-built
// Ass with drifted vectors can never cause an out-of-range read.
fn _section_count(a: &Ass) -> Int {
  var n = a.section_names.len();
  n = _min2(n, a.section_kinds.len());
  n = _min2(n, a.section_starts.len());
  n = _min2(n, a.section_ends.len());
  n = _min2(n, a.section_fmt_starts.len());
  n = _min2(n, a.section_fmt_ends.len());
  return n;
}

// Style row count: the minimum length of the per-style vectors.
fn _style_count(a: &Ass) -> Int {
  var n = a.style_sections.len();
  n = _min2(n, a.style_starts.len());
  n = _min2(n, a.style_ends.len());
  return n;
}

// Event row count: the minimum length of the per-event vectors.
fn _event_count(a: &Ass) -> Int {
  var n = a.event_kinds.len();
  n = _min2(n, a.event_sections.len());
  n = _min2(n, a.event_starts.len());
  n = _min2(n, a.event_ends.len());
  n = _min2(n, a.event_fstarts.len());
  n = _min2(n, a.event_fends.len());
  return n;
}

// Script Info pair count.
fn _info_count(a: &Ass) -> Int {
  var n = a.info_keys.len();
  n = _min2(n, a.info_values.len());
  return n;
}

/// Number of sections.
pub fn ass_section_count(a: &Ass) -> Int {
  return _section_count(a);
}

/// Name of section `i` (trimmed text between the brackets); "" when `i` is
/// negative or out of range.
pub fn ass_section_name(a: &Ass, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= _section_count(a) { return ""; }
  let x: Str = a.section_names[i];
  return x;
}

/// Kind of section `i`: 0 Script Info, 1 V4/V4+ styles, 2 Events, 3 other;
/// -1 when `i` is negative or out of range.
pub fn ass_section_kind(a: &Ass, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _section_count(a) { return -1; }
  let x: Int = a.section_kinds[i];
  return x;
}

/// Number of raw lines preserved for section `i`; 0 when `i` is negative or
/// out of range. Hand-built values are clamped to the shared line pool.
pub fn ass_section_line_count(a: &Ass, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= a.section_starts.len() { return 0; }
  if i >= a.section_ends.len() { return 0; }
  let total = a.section_lines.len();
  var p0: Int = a.section_starts[i];
  var p1: Int = a.section_ends[i];
  if p0 < 0 { p0 = 0; }
  if p0 > total { p0 = total; }
  if p1 < p0 { p1 = p0; }
  if p1 > total { p1 = total; }
  return p1 - p0;
}

/// Raw line `j` of section `i`, verbatim; "" when `i` or `j` is negative or
/// out of range.
pub fn ass_section_line(a: &Ass, i: Int, j: Int) -> Str {
  if i < 0 { return ""; }
  if i >= a.section_starts.len() { return ""; }
  if i >= a.section_ends.len() { return ""; }
  if j < 0 { return ""; }
  let total = a.section_lines.len();
  var p0: Int = a.section_starts[i];
  var p1: Int = a.section_ends[i];
  if p0 < 0 { p0 = 0; }
  if p0 > total { p0 = total; }
  if p1 < p0 { p1 = p0; }
  if p1 > total { p1 = total; }
  if j >= p1 - p0 { return ""; }
  let idx = p0 + j;
  let x: Str = a.section_lines[idx];
  return x;
}

// Start of a section's declared Format range in `format_fields`, clamped to
// the pool; -1 when the section has no Format or `sec` is invalid.
fn _fmt_start(a: &Ass, sec: Int) -> Int {
  if sec < 0 { return -1; }
  if sec >= a.section_fmt_starts.len() { return -1; }
  let fs: Int = a.section_fmt_starts[sec];
  if fs < 0 { return -1; }
  let total = a.format_fields.len();
  if fs > total { return total; }
  return fs;
}

// End (exclusive) of a section's declared Format range, clamped; -1 when the
// section has no Format.
fn _fmt_end(a: &Ass, sec: Int) -> Int {
  if sec < 0 { return -1; }
  if sec >= a.section_fmt_ends.len() { return -1; }
  let fe: Int = a.section_fmt_ends[sec];
  if fe < 0 { return -1; }
  let total = a.format_fields.len();
  var hi = fe;
  if hi > total { hi = total; }
  var lo = 0;
  if sec < a.section_fmt_starts.len() {
    let fs: Int = a.section_fmt_starts[sec];
    if fs > 0 { lo = fs; }
    if lo > total { lo = total; }
  }
  if hi < lo { hi = lo; }
  return hi;
}

/// Number of declared Format fields of section `sec` (for an `[Events]`
/// section without a Format line this is the 10 fields of the documented
/// default); 0 when the section has none or `sec` is invalid.
pub fn ass_format_field_count(a: &Ass, sec: Int) -> Int {
  let lo = _fmt_start(a, sec);
  if lo < 0 { return 0; }
  let hi = _fmt_end(a, sec);
  if hi <= lo { return 0; }
  return hi - lo;
}

/// Declared Format field name `j` of section `sec`; "" when the section has
/// no Format or `j` is negative or out of range.
pub fn ass_format_field(a: &Ass, sec: Int, j: Int) -> Str {
  if j < 0 { return ""; }
  let lo = _fmt_start(a, sec);
  if lo < 0 { return ""; }
  let hi = _fmt_end(a, sec);
  if j >= hi - lo { return ""; }
  let idx = lo + j;
  let x: Str = a.format_fields[idx];
  return x;
}

/// Number of Script Info key: value pairs.
pub fn ass_info_count(a: &Ass) -> Int {
  return _info_count(a);
}

/// Key of Script Info pair `i`; "" when `i` is negative or out of range.
pub fn ass_info_key(a: &Ass, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= _info_count(a) { return ""; }
  let x: Str = a.info_keys[i];
  return x;
}

/// Value of Script Info pair `i`; "" when `i` is negative or out of range.
pub fn ass_info_value(a: &Ass, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= _info_count(a) { return ""; }
  let x: Str = a.info_values[i];
  return x;
}

/// Value of the first Script Info pair whose key equals `key` (first-match),
/// or "" when no pair matches.
pub fn ass_info_value_by_key(a: &Ass, key: Str) -> Str {
  let n = _info_count(a);
  var i = 0;
  while i < n {
    let k: Str = a.info_keys[i];
    if compare.str_compare(k, key) == 0 {
      let v: Str = a.info_values[i];
      return v;
    }
    i = i + 1;
  }
  return "";
}

/// Number of Style rows across all styles sections.
pub fn ass_style_count(a: &Ass) -> Int {
  return _style_count(a);
}

/// Number of fields of Style row `i`; 0 when `i` is negative or out of range.
pub fn ass_style_field_count(a: &Ass, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= a.style_starts.len() { return 0; }
  if i >= a.style_ends.len() { return 0; }
  let total = a.style_fields.len();
  var p0: Int = a.style_starts[i];
  var p1: Int = a.style_ends[i];
  if p0 < 0 { p0 = 0; }
  if p0 > total { p0 = total; }
  if p1 < p0 { p1 = p0; }
  if p1 > total { p1 = total; }
  return p1 - p0;
}

/// Field `j` of Style row `i`, verbatim (the last field is the raw line
/// remainder); "" when `i` or `j` is negative or out of range.
pub fn ass_style_field_at(a: &Ass, i: Int, j: Int) -> Str {
  if i < 0 { return ""; }
  if i >= a.style_starts.len() { return ""; }
  if i >= a.style_ends.len() { return ""; }
  if j < 0 { return ""; }
  let total = a.style_fields.len();
  var p0: Int = a.style_starts[i];
  var p1: Int = a.style_ends[i];
  if p0 < 0 { p0 = 0; }
  if p0 > total { p0 = total; }
  if p1 < p0 { p1 = p0; }
  if p1 > total { p1 = total; }
  if j >= p1 - p0 { return ""; }
  let idx = p0 + j;
  let x: Str = a.style_fields[idx];
  return x;
}

/// Value of the first field of Style row `i` whose declared Format name
/// equals `name` (first-match), or "" when no field matches or `i` is
/// negative or out of range.
pub fn ass_style_field(a: &Ass, i: Int, name: Str) -> Str {
  if i < 0 { return ""; }
  if i >= a.style_sections.len() { return ""; }
  let sec: Int = a.style_sections[i];
  let fs = _fmt_start(a, sec);
  if fs < 0 { return ""; }
  let fe = _fmt_end(a, sec);
  let off = _find_field(&a.format_fields, fs, fe, name);
  if off < 0 { return ""; }
  return ass_style_field_at(a, i, off - fs);
}

/// Number of events (Dialogue plus Comment rows).
pub fn ass_event_count(a: &Ass) -> Int {
  return _event_count(a);
}

/// Number of Dialogue rows.
pub fn ass_dialogue_count(a: &Ass) -> Int {
  let n = _event_count(a);
  var count = 0;
  var i = 0;
  while i < n {
    let k: Int = a.event_kinds[i];
    if k == 0 { count = count + 1; }
    i = i + 1;
  }
  return count;
}

/// Number of Comment rows.
pub fn ass_comment_count(a: &Ass) -> Int {
  let n = _event_count(a);
  var count = 0;
  var i = 0;
  while i < n {
    let k: Int = a.event_kinds[i];
    if k == 1 { count = count + 1; }
    i = i + 1;
  }
  return count;
}

/// Kind of event `i`: 0 Dialogue, 1 Comment; -1 when `i` is negative or out
/// of range.
pub fn ass_event_kind(a: &Ass, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= _event_count(a) { return -1; }
  let x: Int = a.event_kinds[i];
  return x;
}

/// Number of fields of event `i`; 0 when `i` is negative or out of range.
pub fn ass_event_field_count(a: &Ass, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= a.event_fstarts.len() { return 0; }
  if i >= a.event_fends.len() { return 0; }
  let total = a.event_fields.len();
  var p0: Int = a.event_fstarts[i];
  var p1: Int = a.event_fends[i];
  if p0 < 0 { p0 = 0; }
  if p0 > total { p0 = total; }
  if p1 < p0 { p1 = p0; }
  if p1 > total { p1 = total; }
  return p1 - p0;
}

/// Field `j` of event `i`, verbatim (the last field is the raw line
/// remainder, so commas in Text are preserved); "" when `i` or `j` is
/// negative or out of range.
pub fn ass_event_field_at(a: &Ass, i: Int, j: Int) -> Str {
  if i < 0 { return ""; }
  if i >= a.event_fstarts.len() { return ""; }
  if i >= a.event_fends.len() { return ""; }
  if j < 0 { return ""; }
  let total = a.event_fields.len();
  var p0: Int = a.event_fstarts[i];
  var p1: Int = a.event_fends[i];
  if p0 < 0 { p0 = 0; }
  if p0 > total { p0 = total; }
  if p1 < p0 { p1 = p0; }
  if p1 > total { p1 = total; }
  if j >= p1 - p0 { return ""; }
  let idx = p0 + j;
  let x: Str = a.event_fields[idx];
  return x;
}

/// Value of the first field of event `i` whose declared Format name equals
/// `name` (first-match), or "" when no field matches or `i` is negative or
/// out of range.
pub fn ass_event_field(a: &Ass, i: Int, name: Str) -> Str {
  if i < 0 { return ""; }
  if i >= a.event_sections.len() { return ""; }
  let sec: Int = a.event_sections[i];
  let fs = _fmt_start(a, sec);
  if fs < 0 { return ""; }
  let fe = _fmt_end(a, sec);
  let off = _find_field(&a.format_fields, fs, fe, name);
  if off < 0 { return ""; }
  return ass_event_field_at(a, i, off - fs);
}

/// Parsed Start of event `i` in centiseconds; -1 when `i` is negative or out
/// of range or the section's Format has no Start field.
pub fn ass_event_start_cs(a: &Ass, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= a.event_starts.len() { return -1; }
  let x: Int = a.event_starts[i];
  if x < 0 { return -1; }
  return x;
}

/// Parsed End of event `i` in centiseconds; -1 when `i` is negative or out
/// of range or the section's Format has no End field.
pub fn ass_event_end_cs(a: &Ass, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= a.event_ends.len() { return -1; }
  let x: Int = a.event_ends[i];
  if x < 0 { return -1; }
  return x;
}

/// Value of the first field of event `i` named Text (first-match), captured
/// raw to the end of the line; "" when absent or out of range. `\N`, `\n`
/// and `{...}` override blocks are returned as raw bytes.
pub fn ass_event_text(a: &Ass, i: Int) -> Str {
  return ass_event_field(a, i, "Text");
}

/// Value of the first field of event `i` named Style (first-match); "" when
/// absent or out of range.
pub fn ass_event_style(a: &Ass, i: Int) -> Str {
  return ass_event_field(a, i, "Style");
}
