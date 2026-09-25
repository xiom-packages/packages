// XIOM -- xiom.hl7: HL7 v2.x pipe-delimited message codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the exact grammar, error catalog and test
// plan):
//   * segment lines separated by CR; LF and CRLF are accepted on parse;
//   * MSH special handling: the field separator is the byte after "MSH"
//     (MSH.1) and the four encoding characters follow (MSH.2): component,
//     repetition, escape and subcomponent;
//   * every segment is split into fields; fields are read as repetitions,
//     components and subcomponents on demand;
//   * flat parallel storage with offsets: seg_names / seg_off / seg_len /
//     fields (no Vec[StructType]);
//   * accessors (segment count, segment name by index, segment index by
//     name, field / repetition / component / subcomponent as Str) and a
//     builder that appends segments and fields with separator-aware
//     escaping (data-safe or structure-preserving);
//   * validation (MSH first, exactly four encoding characters, no empty
//     segment lines, non-empty message) and a deterministic Err(Str)
//     catalog.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[fn] dispatch,
//     no Vec[StructType];
//   * byte-wise scanning with xiom.string.byte_at; every byte read is
//     widened once with (byte_at(...) as Int) & 0xFF so no UInt8 value is
//     compared against an integer literal or an unchecked constant;
//   * output bytes are collected in a Vec[UInt8] and materialized once with
//     xiom.string.builder.sb_to_str;
//   * Ok/Err for Result[Message, Str] are constructed only in the tiny leaf
//     helpers _ok_msg / _err_msg;
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on a Str read from a Vec[Str] element lowers to a pointer
//     comparison); Vec elements are read into explicitly typed locals first.

module xiom.hl7

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(m) for Result[Message, Str].
fn _ok_msg(m: Message) -> Result[Message, Str] {
  return Ok(m);
}

// Err(s) for Result[Message, Str].
fn _err_msg(s: Str) -> Result[Message, Str] {
  return Err(s);
}

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _HL7_LF: Int = 10;
const _HL7_CR: Int = 13;
const _HL7_SEP_MIN: Int = 33;   // '!', the first legal separator byte
const _HL7_SEP_MAX: Int = 126;  // '~', the last legal separator byte

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed or builder-held HL7 v2 message. The five separator Strs come from
/// MSH.1 (field) and MSH.2 (component, repetition, escape, subcomponent).
/// Segments are flat: segment `i` is `seg_names[i]` and owns the `seg_len[i]`
/// raw field texts starting at `fields[seg_off[i]]`; field numbers are
/// 1-based, so segment field `f` is `fields[seg_off[i] + f - 1]`. For MSH,
/// field 1 is the field separator and field 2 the four encoding characters,
/// exactly as they appear on the wire. The three index vectors are
/// index-aligned and a segment's fields are contiguous in `fields`.
/// `Vec[StructType]` is unsupported, so there is deliberately no
/// `Vec[Segment]`.
pub type Message = {
  field_sep: Str;
  comp_sep: Str;
  rep_sep: Str;
  esc_sep: Str;
  sub_sep: Str;
  seg_names: Vec[Str];
  seg_off: Vec[Int];
  seg_len: Vec[Int];
  fields: Vec[Str];
}

// --------------------------------------------------
//  Byte and string helpers
// --------------------------------------------------

// Read byte i of s widened to 0..255. Every byte read in this module goes
// through here.
fn _byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for the ASCII alphanumerics A-Z, a-z, 0-9. Separators must not be
// alphanumeric so data bytes cannot be mistaken for delimiters.
fn _is_alnum(b: Int) -> Bool {
  if b >= 48 && b <= 57 {
    return true;
  }
  if b >= 65 && b <= 90 {
    return true;
  }
  if b >= 97 && b <= 122 {
    return true;
  }
  return false;
}

// True for a legal HL7 separator byte: printable ASCII ('!'..'~', i.e.
// 0x21..0x7E) that is not alphanumeric. CR, LF, SPACE, DEL and every
// non-ASCII byte are rejected.
fn _valid_sep_byte(b: Int) -> Bool {
  if b < _HL7_SEP_MIN || b > _HL7_SEP_MAX {
    return false;
  }
  return !_is_alnum(b);
}

// True when a and b are byte-equal (BUG 17: through str_compare, never `==`).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Decimal representation of an Int, used only inside error messages.
fn _int_to_str(v: Int) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_int(&mut sb, v);
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Separator splitting
// --------------------------------------------------

// Number of separator-delimited parts of `text`: 1 when `sep` is not a
// one-byte Str or does not occur in `text`, and 1 for an empty text.
fn _count_parts(text: Str, sep: Str) -> Int {
  if sep.len() != 1 {
    return 1;
  }
  let sb = _byte_at(sep, 0);
  var count = 1;
  let n = text.len();
  var i = 0;
  while i < n {
    if _byte_at(text, i) == sb {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// 1-based part `index` of `text` split on the one-byte `sep`; None when
// `index` is below 1 or beyond the last part. Empty parts are preserved (a
// trailing or doubled separator yields an empty Str), and a non-one-byte
// `sep` makes part 1 the whole text.
fn _part(text: Str, sep: Str, index: Int) -> Option[Str] {
  if index < 1 {
    return None;
  }
  if sep.len() != 1 {
    if index == 1 {
      return Some(text);
    }
    return None;
  }
  let sb = _byte_at(sep, 0);
  let n = text.len();
  var part = 1;
  var start = 0;
  var i = 0;
  while i <= n {
    let at_end = i == n;
    var is_sep = false;
    if !at_end {
      if _byte_at(text, i) == sb {
        is_sep = true;
      }
    }
    if at_end || is_sep {
      if part == index {
        return Some(string.str_slice(text, start, i));
      }
      part = part + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  return None;
}

// --------------------------------------------------
//  Segment-line parsing helpers
// --------------------------------------------------

// Parse the MSH segment line into `m`: set the five separators and store
// field 1 (the field separator) and field 2 (the four encoding characters)
// plus any later fields. The caller checked that the line starts with "MSH".
// Returns "" on success, or the deterministic "hl7: ..." error.
fn _parse_msh_line(m: &mut Message, line: Str) -> Str {
  let n = line.len();
  if n < 4 {
    return "hl7: malformed MSH segment: too short";
  }
  let fs_b = _byte_at(line, 3);
  if !_valid_sep_byte(fs_b) {
    return "hl7: invalid separator";
  }
  var enc_end = n;
  var i = 4;
  while i < n {
    if _byte_at(line, i) == fs_b {
      enc_end = i;
      break;
    }
    i = i + 1;
  }
  let enc_len = enc_end - 4;
  if enc_len != 4 {
    return "hl7: malformed MSH segment: expected 4 encoding characters, got " + _int_to_str(enc_len);
  }
  let enc = string.str_slice(line, 4, enc_end);
  var j = 0;
  while j < 4 {
    let b = _byte_at(enc, j);
    if !_valid_sep_byte(b) {
      return "hl7: invalid separator";
    }
    if b == fs_b {
      return "hl7: invalid separator";
    }
    var k = 0;
    while k < j {
      if _byte_at(enc, k) == b {
        return "hl7: invalid separator";
      }
      k = k + 1;
    }
    j = j + 1;
  }
  let fs = string.str_slice(line, 3, 4);
  m.field_sep = fs;
  m.comp_sep = string.str_slice(enc, 0, 1);
  m.rep_sep = string.str_slice(enc, 1, 2);
  m.esc_sep = string.str_slice(enc, 2, 3);
  m.sub_sep = string.str_slice(enc, 3, 4);
  let start = m.fields.len();
  m.fields.push(fs);
  m.fields.push(enc);
  var count = 2;
  if enc_end < n {
    var p = enc_end + 1;
    var p_start = enc_end + 1;
    while p <= n {
      let at_end = p == n;
      var is_sep = false;
      if !at_end {
        if _byte_at(line, p) == fs_b {
          is_sep = true;
        }
      }
      if at_end || is_sep {
        m.fields.push(string.str_slice(line, p_start, p));
        count = count + 1;
        p_start = p + 1;
      }
      p = p + 1;
    }
  }
  m.seg_names.push("MSH");
  m.seg_off.push(start);
  m.seg_len.push(count);
  return "";
}

// Parse one non-MSH segment line into `m` using m.field_sep: the segment name
// runs up to the first field separator (or to the end of the line when there
// is none, giving a name-only segment with zero fields), and everything after
// it is split into fields. Returns "" on success, or "hl7: empty segment
// name" when the line starts with the field separator.
fn _parse_segment_line(m: &mut Message, line: Str) -> Str {
  let n = line.len();
  let fs_b = _byte_at(m.field_sep, 0);
  var name_end = n;
  var i = 0;
  while i < n {
    if _byte_at(line, i) == fs_b {
      name_end = i;
      break;
    }
    i = i + 1;
  }
  if name_end == 0 {
    return "hl7: empty segment name";
  }
  let name = string.str_slice(line, 0, name_end);
  let start = m.fields.len();
  var count = 0;
  if name_end < n {
    var p = name_end + 1;
    var p_start = name_end + 1;
    while p <= n {
      let at_end = p == n;
      var is_sep = false;
      if !at_end {
        if _byte_at(line, p) == fs_b {
          is_sep = true;
        }
      }
      if at_end || is_sep {
        m.fields.push(string.str_slice(line, p_start, p));
        count = count + 1;
        p_start = p + 1;
      }
      p = p + 1;
    }
  }
  m.seg_names.push(name);
  m.seg_off.push(start);
  m.seg_len.push(count);
  return "";
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one in-memory HL7 v2 message.
/// Params: text - the whole message. Segments end at CR (0x0D); LF (0x0A) and
/// CRLF are accepted as segment terminators too, and a single trailing
/// terminator adds no segment. Text holding only terminators (or nothing) is
/// an empty message.
/// Returns: Ok(Message) when the first segment is a well-formed MSH carrying
/// exactly four valid, distinct encoding characters (see SPEC.md); Err with a
/// deterministic "hl7: ..." message otherwise.
/// Error case: "hl7: empty message", "hl7: missing MSH segment",
/// "hl7: malformed MSH segment: too short", "hl7: malformed MSH segment:
/// expected 4 encoding characters, got N", "hl7: invalid separator",
/// "hl7: empty segment name".
/// Complexity: O(text length).
pub fn hl7_parse(text: Str) -> Result[Message, Str] {
  let n = text.len();
  var has_content = false;
  var h = 0;
  while h < n {
    let hb = _byte_at(text, h);
    if hb != _HL7_CR && hb != _HL7_LF {
      has_content = true;
    }
    h = h + 1;
  }
  if !has_content {
    return _err_msg("hl7: empty message");
  }
  var m = Message{
    field_sep: "";
    comp_sep: "";
    rep_sep: "";
    esc_sep: "";
    sub_sep: "";
    seg_names: Vec[Str].new();
    seg_off: Vec[Int].new();
    seg_len: Vec[Int].new();
    fields: Vec[Str].new();
  };
  var line_start = 0;
  var i = 0;
  var seg_no = 0;
  while i <= n {
    if i == n || _byte_at(text, i) == _HL7_CR || _byte_at(text, i) == _HL7_LF {
      let le = i;
      var after = i;
      if i < n {
        if _byte_at(text, i) == _HL7_CR && i + 1 < n && _byte_at(text, i + 1) == _HL7_LF {
          after = i + 2;
        } else {
          after = i + 1;
        }
      }
      if le == line_start {
        if i == n {
          // The artifact line after the final terminator is not a segment.
          break;
        }
        return _err_msg("hl7: empty segment name");
      }
      let line = string.str_slice(text, line_start, le);
      if seg_no == 0 {
        if !string.str_starts_with(line, "MSH") {
          return _err_msg("hl7: missing MSH segment");
        }
        let e_msh = _parse_msh_line(&mut m, line);
        if e_msh.len() > 0 {
          return _err_msg(e_msh);
        }
      } else {
        let e_seg = _parse_segment_line(&mut m, line);
        if e_seg.len() > 0 {
          return _err_msg(e_seg);
        }
      }
      seg_no = seg_no + 1;
      if i == n {
        break;
      }
      line_start = after;
      i = after;
    } else {
      i = i + 1;
    }
  }
  return _ok_msg(m);
}

// --------------------------------------------------
//  Model accessors
// --------------------------------------------------

/// Number of segments in the message.
/// Error case: none.
/// Complexity: O(1).
pub fn hl7_seg_count(m: &Message) -> Int {
  return m.seg_names.len();
}

/// Name of segment `i` (zero-based); None when `i` is out of range. Names are
/// returned exactly as they appear on the wire (not case-folded).
/// Error case: none.
/// Complexity: O(1).
pub fn hl7_seg_name(m: &Message, i: Int) -> Option[Str] {
  if i < 0 || i >= m.seg_names.len() {
    return None;
  }
  let v: Str = m.seg_names[i];
  return Some(v);
}

/// Index of the first segment named `name` (byte-exact, case-sensitive);
/// None when the message has no such segment.
/// Error case: none.
/// Complexity: O(segment count).
pub fn hl7_seg_index(m: &Message, name: Str) -> Option[Int] {
  var i = 0;
  while i < m.seg_names.len() {
    let k: Str = m.seg_names[i];
    if _streq(k, name) {
      return Some(i);
    }
    i = i + 1;
  }
  return None;
}

/// Number of stored fields of segment `i`; 0 when `i` is out of range. For
/// MSH the count includes field 1 (the field separator) and field 2 (the
/// encoding characters). The codec does not require segments of the same type
/// to have equal field counts: optional trailing HL7 fields may be absent, so
/// the count is reported per segment.
/// Error case: none.
/// Complexity: O(1).
pub fn hl7_seg_field_count(m: &Message, i: Int) -> Int {
  if i < 0 || i >= m.seg_len.len() {
    return 0;
  }
  let c: Int = m.seg_len[i];
  return c;
}

/// The field separator declared by MSH.1 (one byte).
/// Error case: none.
/// Complexity: O(1).
pub fn hl7_field_sep(m: &Message) -> Str {
  return m.field_sep;
}

/// The four encoding characters of MSH.2 in order: component, repetition,
/// escape, subcomponent.
/// Error case: none.
/// Complexity: O(1).
pub fn hl7_encoding(m: &Message) -> Str {
  return m.comp_sep + m.rep_sep + m.esc_sep + m.sub_sep;
}

/// Raw text of field `f` (1-based HL7 field number) of segment `i`; None when
/// the segment or field is out of range. The text is exactly as it appears on
/// the wire: repetitions, components and subcomponents are not split and
/// escape sequences are not decoded. For MSH, field 1 is the field separator
/// and field 2 the encoding characters.
/// Error case: none.
/// Complexity: O(1).
pub fn hl7_field(m: &Message, i: Int, f: Int) -> Option[Str] {
  if i < 0 || i >= m.seg_len.len() {
    return None;
  }
  if f < 1 {
    return None;
  }
  let c: Int = m.seg_len[i];
  if f > c {
    return None;
  }
  let off: Int = m.seg_off[i];
  let v: Str = m.fields[off + f - 1];
  return Some(v);
}

/// Number of repetitions of field `f` of segment `i` (the field split on the
/// repetition separator); 0 when the field is out of range. A field without
/// repetitions has count 1.
/// Error case: none.
/// Complexity: O(field length).
pub fn hl7_rep_count(m: &Message, i: Int, f: Int) -> Int {
  let raw = hl7_field(m, i, f);
  match raw {
    Some(v) => { return _count_parts(v, m.rep_sep); },
    None => { return 0; },
  }
  return 0;
}

/// Repetition `r` (1-based) of field `f` of segment `i`; None when the field
/// or repetition is out of range. Repetition 1 of a field without "~" is the
/// whole field.
/// Error case: none.
/// Complexity: O(field length).
pub fn hl7_rep(m: &Message, i: Int, f: Int, r: Int) -> Option[Str] {
  let raw = hl7_field(m, i, f);
  match raw {
    Some(v) => { return _part(v, m.rep_sep, r); },
    None => { return None; },
  }
  return None;
}

/// Number of components of repetition `r` of field `f` of segment `i`; 0 when
/// the field or repetition is out of range.
/// Error case: none.
/// Complexity: O(field length).
pub fn hl7_comp_count(m: &Message, i: Int, f: Int, r: Int) -> Int {
  let rep = hl7_rep(m, i, f, r);
  match rep {
    Some(v) => { return _count_parts(v, m.comp_sep); },
    None => { return 0; },
  }
  return 0;
}

/// Component `c` (1-based) of repetition `r` of field `f` of segment `i`;
/// None when any index is out of range. Empty components are preserved.
/// Error case: none.
/// Complexity: O(field length).
pub fn hl7_comp(m: &Message, i: Int, f: Int, r: Int, c: Int) -> Option[Str] {
  let rep = hl7_rep(m, i, f, r);
  match rep {
    Some(v) => { return _part(v, m.comp_sep, c); },
    None => { return None; },
  }
  return None;
}

/// Number of subcomponents of component `c` of repetition `r` of field `f` of
/// segment `i`; 0 when any index is out of range.
/// Error case: none.
/// Complexity: O(field length).
pub fn hl7_sub_count(m: &Message, i: Int, f: Int, r: Int, c: Int) -> Int {
  let comp = hl7_comp(m, i, f, r, c);
  match comp {
    Some(v) => { return _count_parts(v, m.sub_sep); },
    None => { return 0; },
  }
  return 0;
}

/// Subcomponent `s` (1-based) of component `c` of repetition `r` of field `f`
/// of segment `i`; None when any index is out of range. Empty subcomponents
/// are preserved.
/// Error case: none.
/// Complexity: O(field length).
pub fn hl7_sub(m: &Message, i: Int, f: Int, r: Int, c: Int, s: Int) -> Option[Str] {
  let comp = hl7_comp(m, i, f, r, c);
  match comp {
    Some(v) => { return _part(v, m.sub_sep, s); },
    None => { return None; },
  }
  return None;
}

// --------------------------------------------------
//  Writing
// --------------------------------------------------

/// Serialize a message back to wire text.
/// Params: m - a parsed or builder-held message.
/// Returns: one line per segment, each terminated by CR including the last
/// one. MSH is written as "MSH" + MSH.1 + MSH.2 + the remaining fields; every
/// other segment as its name followed by its fields. Field texts are emitted
/// verbatim, so a parsed message round-trips byte-exact and a value added
/// through the builder is already escaped. An empty message (no segments)
/// yields "".
/// Error case: none.
/// Complexity: O(total field bytes).
pub fn hl7_write(m: &Message) -> Str {
  let segs = m.seg_names.len();
  if segs == 0 {
    return "";
  }
  var out = Vec[UInt8].new();
  var seg = 0;
  while seg < segs {
    if seg > 0 {
      out.push(_HL7_CR as UInt8);
    }
    let name: Str = m.seg_names[seg];
    builder.sb_push_str(&mut out, name);
    let off: Int = m.seg_off[seg];
    let cnt: Int = m.seg_len[seg];
    if _streq(name, "MSH") && cnt >= 2 {
      let f1: Str = m.fields[off];
      let f2: Str = m.fields[off + 1];
      builder.sb_push_str(&mut out, f1);
      builder.sb_push_str(&mut out, f2);
      var k = 2;
      while k < cnt {
        builder.sb_push_str(&mut out, m.field_sep);
        let fk: Str = m.fields[off + k];
        builder.sb_push_str(&mut out, fk);
        k = k + 1;
      }
    } else {
      var k = 0;
      while k < cnt {
        builder.sb_push_str(&mut out, m.field_sep);
        let fk: Str = m.fields[off + k];
        builder.sb_push_str(&mut out, fk);
        k = k + 1;
      }
    }
    seg = seg + 1;
  }
  out.push(_HL7_CR as UInt8);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Builder
// --------------------------------------------------

/// A fresh builder message with the canonical separators: field "|",
/// component "^", repetition "~", escape "\", subcomponent "&". It holds no
/// segment; open the first one with `hl7_builder_segment`.
/// Error case: none.
/// Complexity: O(1).
pub fn hl7_builder_new() -> Message {
  return Message{
    field_sep: "|";
    comp_sep: "^";
    rep_sep: "~";
    esc_sep: "\\";
    sub_sep: "&";
    seg_names: Vec[Str].new();
    seg_off: Vec[Int].new();
    seg_len: Vec[Int].new();
    fields: Vec[Str].new();
  };
}

/// A fresh builder with explicit separators.
/// Params: field_sep - one byte; encoding - exactly four bytes holding
/// component, repetition, escape and subcomponent.
/// Returns: Ok(Message) when every separator is a legal separator byte
/// (printable ASCII, not alphanumeric), the four encoding characters are
/// pairwise distinct and none equals the field separator; Err("hl7: ...")
/// otherwise, using the same messages as MSH validation.
/// Error case: "hl7: invalid separator", "hl7: malformed MSH segment:
/// expected 4 encoding characters, got N".
/// Complexity: O(1).
pub fn hl7_builder_with_separators(field_sep: Str, encoding: Str) -> Result[Message, Str] {
  if field_sep.len() != 1 {
    return _err_msg("hl7: invalid separator");
  }
  let fb = _byte_at(field_sep, 0);
  if !_valid_sep_byte(fb) {
    return _err_msg("hl7: invalid separator");
  }
  if encoding.len() != 4 {
    return _err_msg("hl7: malformed MSH segment: expected 4 encoding characters, got " + _int_to_str(encoding.len()));
  }
  var j = 0;
  while j < 4 {
    let b = _byte_at(encoding, j);
    if !_valid_sep_byte(b) {
      return _err_msg("hl7: invalid separator");
    }
    if b == fb {
      return _err_msg("hl7: invalid separator");
    }
    var k = 0;
    while k < j {
      if _byte_at(encoding, k) == b {
        return _err_msg("hl7: invalid separator");
      }
      k = k + 1;
    }
    j = j + 1;
  }
  return _ok_msg(Message{
    field_sep: field_sep;
    comp_sep: string.str_slice(encoding, 0, 1);
    rep_sep: string.str_slice(encoding, 1, 2);
    esc_sep: string.str_slice(encoding, 2, 3);
    sub_sep: string.str_slice(encoding, 3, 4);
    seg_names: Vec[Str].new();
    seg_off: Vec[Int].new();
    seg_len: Vec[Int].new();
    fields: Vec[Str].new();
  });
}

/// Open a new segment named `name` in builder `m` and make it the target of
/// `hl7_builder_field`. "MSH" may only be the first segment; opening it
/// stores field 1 (the field separator) and field 2 (the encoding characters)
/// immediately, so the first field appended afterwards is MSH.3.
/// Params: m - the builder; name - the segment name (non-empty).
/// Returns: "" on success. "hl7: empty segment name" for an empty name,
/// "hl7: missing MSH segment" when the first segment is not MSH, and
/// "hl7: malformed MSH segment: MSH must be the first segment" when MSH is
/// opened later.
/// Complexity: O(name length).
pub fn hl7_builder_segment(m: &mut Message, name: Str) -> Str {
  if name.len() == 0 {
    return "hl7: empty segment name";
  }
  let start = m.fields.len();
  if _streq(name, "MSH") {
    if m.seg_names.len() != 0 {
      return "hl7: malformed MSH segment: MSH must be the first segment";
    }
    let fs: Str = m.field_sep;
    let cs: Str = m.comp_sep;
    let rs: Str = m.rep_sep;
    let es: Str = m.esc_sep;
    let ss: Str = m.sub_sep;
    let enc: Str = cs + rs + es + ss;
    m.fields.push(fs);
    m.fields.push(enc);
    m.seg_names.push(name);
    m.seg_off.push(start);
    m.seg_len.push(2);
    return "";
  }
  if m.seg_names.len() == 0 {
    return "hl7: missing MSH segment";
  }
  m.seg_names.push(name);
  m.seg_off.push(start);
  m.seg_len.push(0);
  return "";
}

/// Append a data field to the segment last opened with `hl7_builder_segment`,
/// escaping every separator so the value cannot break the message structure:
/// field separator -> "\F\", component -> "\S\", repetition -> "\R\", escape
/// -> "\E\", subcomponent -> "\T\" (each written with the message's escape
/// character). CR and LF are rejected because a segment is one line. Use
/// `hl7_builder_field_structured` to append a field whose component,
/// repetition and subcomponent separators are meant as structure.
/// Params: m - the builder; value - the unescaped field text.
/// Returns: "" on success; "hl7: no open segment" when no segment is open;
/// "hl7: field contains a line terminator" when `value` holds CR or LF.
/// Complexity: O(value length).
pub fn hl7_builder_field(m: &mut Message, value: Str) -> Str {
  if m.seg_names.len() == 0 {
    return "hl7: no open segment";
  }
  var i = 0;
  while i < value.len() {
    let b = _byte_at(value, i);
    if b == _HL7_CR || b == _HL7_LF {
      return "hl7: field contains a line terminator";
    }
    i = i + 1;
  }
  let fs: Str = m.field_sep;
  let cs: Str = m.comp_sep;
  let rs: Str = m.rep_sep;
  let es: Str = m.esc_sep;
  let ss: Str = m.sub_sep;
  let escaped = _escape_field(value, fs, cs, rs, es, ss, true);
  m.fields.push(escaped);
  let last = m.seg_len.len() - 1;
  let cur: Int = m.seg_len[last];
  m.seg_len[last] = cur + 1;
  return "";
}

/// Append a wire-level field to the segment last opened with
/// `hl7_builder_segment`: the component, repetition and subcomponent
/// separators in `value` are kept as structure, while the field separator ->
/// "\F\" and the escape character -> "\E\" are escaped so the field cannot be
/// split or start a stray escape sequence. CR and LF are rejected because a
/// segment is one line. Use `hl7_builder_field` instead when `value` is a leaf
/// data value that may contain any separator.
/// Params: m - the builder; value - the field text with HL7 structure.
/// Returns: "" on success; "hl7: no open segment" when no segment is open;
/// "hl7: field contains a line terminator" when `value` holds CR or LF.
/// Complexity: O(value length).
pub fn hl7_builder_field_structured(m: &mut Message, value: Str) -> Str {
  if m.seg_names.len() == 0 {
    return "hl7: no open segment";
  }
  var i = 0;
  while i < value.len() {
    let b = _byte_at(value, i);
    if b == _HL7_CR || b == _HL7_LF {
      return "hl7: field contains a line terminator";
    }
    i = i + 1;
  }
  let fs: Str = m.field_sep;
  let cs: Str = m.comp_sep;
  let rs: Str = m.rep_sep;
  let es: Str = m.esc_sep;
  let ss: Str = m.sub_sep;
  let escaped = _escape_field(value, fs, cs, rs, es, ss, false);
  m.fields.push(escaped);
  let last = m.seg_len.len() - 1;
  let cur: Int = m.seg_len[last];
  m.seg_len[last] = cur + 1;
  return "";
}

// Escape one field value for the builder. The field separator and the escape
// character always become escape + code + escape (codes F and E). With
// `escape_all`, the component, repetition and subcomponent separators are
// escaped too (codes S, R and T); without it they pass through as structure.
// Any other byte passes through; the caller already rejected CR and LF. A
// separator that is not a one-byte Str cannot match, so hand-built incomplete
// Messages degrade to plain copying.
fn _escape_field(value: Str, fs: Str, comp: Str, rep: Str, esc: Str, sub: Str, escape_all: Bool) -> Str {
  var fs_b = -1;
  var comp_b = -1;
  var rep_b = -1;
  var esc_b = -1;
  var sub_b = -1;
  if fs.len() == 1 {
    fs_b = _byte_at(fs, 0);
  }
  if comp.len() == 1 {
    comp_b = _byte_at(comp, 0);
  }
  if rep.len() == 1 {
    rep_b = _byte_at(rep, 0);
  }
  if esc.len() == 1 {
    esc_b = _byte_at(esc, 0);
  }
  if sub.len() == 1 {
    sub_b = _byte_at(sub, 0);
  }
  let n = value.len();
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b = _byte_at(value, i);
    var code = "";
    if b == fs_b {
      code = "F";
    } elif b == esc_b {
      code = "E";
    } elif escape_all && b == comp_b {
      code = "S";
    } elif escape_all && b == rep_b {
      code = "R";
    } elif escape_all && b == sub_b {
      code = "T";
    }
    if code.len() > 0 {
      builder.sb_push_str(&mut out, esc);
      builder.sb_push_str(&mut out, code);
      builder.sb_push_str(&mut out, esc);
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
