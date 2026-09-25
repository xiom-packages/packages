// XIOM -- xiom.fix: FIX tag=value message codec with SOH framing
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the exact grammar, validation rules,
// error catalog and test plan):
//   * SOH (0x01) field separator; ordered tag=value pairs stored flat as a
//     tag vector plus value spans into the input text (no Vec[StructType]);
//   * duplicate tags preserved in wire order; first/last accessors;
//   * validation: tag 8 BeginString is the first field and non-empty, tag 9
//     BodyLength is the second field and equals the byte count between the
//     SOH after tag 9 and the start of "10=", tag 35 MsgType is required and
//     non-empty, tag 10 CheckSum equals the sum of all bytes before "10="
//     modulo 256 written as exactly three digits;
//   * canonical emit (fix_emit) that recomputes tags 9 and 10.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[fn] dispatch,
//     no Vec[StructType], no Vec[Float64];
//   * byte-wise scanning with xiom.string.byte_at; every byte read is widened
//     with (byte_at(...) as Int) & 0xFF, so no UInt8 is compared against an
//     unwidened constant;
//   * output bytes are collected in a Vec[UInt8] and materialized once with
//     xiom.string.builder.sb_to_str, never from bytes that may contain 0x00;
//   * Ok/Err for Result[FixMessage, Str] are constructed only in the tiny
//     leaf helpers _ok_fix / _err_fix (constructing a struct-payload Result
//     inside a larger function miscompiles in this compiler);
//   * plain Str values are never compared with `==`; no Str is read out of a
//     Vec in this module, every decision is made on Int-widened bytes.

module xiom.fix

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(m) for Result[FixMessage, Str].
fn _ok_fix(m: FixMessage) -> Result[FixMessage, Str] {
  return Ok(m);
}

// Err(s) for Result[FixMessage, Str].
fn _err_fix(s: Str) -> Result[FixMessage, Str] {
  return Err(s);
}

// Ok(s) for Result[Str, Str] (used by fix_emit only).
fn _ok_out(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

// Err(s) for Result[Str, Str] (used by fix_emit only).
fn _err_out(s: Str) -> Result[Str, Str] {
  return Err(s);
}

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _FIX_SOH: Int = 1;       // field separator 0x01
const _FIX_CHR_8: Int = 56;    // '8'
const _FIX_CHR_9: Int = 57;    // '9'
const _FIX_ZERO: Int = 48;     // '0'
const _FIX_NINE: Int = 57;     // '9'
const _FIX_EQ: Int = 61;       // '='

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed FIX message. `raw` is the exact input text; `tags[i]` is the tag
/// number of field `i` and its value is the byte span
/// raw[starts[i], ends[i]). There is deliberately no Vec[StructType]: the
/// message is three index-aligned vectors plus the validated scalars.
/// Duplicate tags keep their wire order; a parsed message contains tags 8, 9
/// and 10 exactly once (duplicates are rejected). `body_length` and
/// `checksum` hold the validated values of tags 9 and 10. The accessors
/// guard against hand-built messages whose vectors are not aligned.
pub type FixMessage = {
  raw: Str;
  tags: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
  body_length: Int;
  checksum: Int;
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Read byte `i` of `s` widened to 0..255.
fn _byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True when `b` is an ASCII decimal digit.
fn _is_digit(b: Int) -> Bool {
  if b < _FIX_ZERO { return false; }
  return b <= _FIX_NINE;
}

// Index of the first SOH at or after `from`, or -1.
fn _find_soh(s: Str, from: Int) -> Int {
  let n = s.len();
  var i = from;
  while i < n {
    if _byte_at(s, i) == _FIX_SOH {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first '=' in [from, end), or -1.
fn _find_eq(s: Str, from: Int, end: Int) -> Int {
  var i = from;
  while i < end {
    if _byte_at(s, i) == _FIX_EQ {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Decimal value of the digit run s[from, to); -1 when the run is empty, is
// longer than 9 digits, or holds a non-digit byte. Leading zeros are
// accepted ("007" is 7); the cap keeps the accumulator inside Int.
fn _parse_uint(s: Str, from: Int, to: Int) -> Int {
  let width = to - from;
  if width <= 0 || width > 9 {
    return -1;
  }
  var acc = 0;
  var i = from;
  while i < to {
    let b = _byte_at(s, i);
    if !_is_digit(b) {
      return -1;
    }
    acc = acc * 10 + (b - _FIX_ZERO);
    i = i + 1;
  }
  return acc;
}

// Decimal representation of `v`; used inside error messages only. Built from
// ASCII digits, so sb_to_str never sees a 0x00 byte.
fn _int_to_str(v: Int) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_int(&mut sb, v);
  return builder.sb_to_str(&sb);
}

// "<prefix>N" for the offset-carrying error messages.
fn _at_offset(prefix: Str, at: Int) -> Str {
  return prefix + _int_to_str(at);
}

// --------------------------------------------------
//  Field scanning
// --------------------------------------------------

// Scan every field of `raw` into `m` and validate the FIX frame. Returns ""
// on success, or the deterministic "fix: ..." message of the first failed
// check. On success `tags` / `starts` / `ends` are index-aligned and the
// message is well formed: field 0 is tag 8 (non-empty), field 1 is tag 9, a
// tag 35 field exists and is non-empty, the tag-10 field is the last one,
// and its BodyLength and CheckSum values are correct.
//
// Check order: per field, framing checks run first (tag digits, '=', field
// order, duplicates, empty BeginString/MsgType), then at the tag-10 field:
// trailing bytes, BodyLength format, BodyLength value, MsgType presence,
// CheckSum format, CheckSum value. The first failing check is reported.
fn _scan_fields(raw: Str, m: &mut FixMessage) -> Str {
  let n = raw.len();
  var i = 0;
  var field = 0;
  var seen35 = false;
  while i < n {
    let soh = _find_soh(raw, i);
    var field_end = n;
    var after = n;
    if soh >= 0 {
      field_end = soh;
      after = soh + 1;
    }
    let eq = _find_eq(raw, i, field_end);
    if eq < 0 {
      return _at_offset("fix: missing '=' in field at offset ", i);
    }
    if eq == i {
      return _at_offset("fix: non-digit tag at offset ", i);
    }
    var tag = 0;
    var ndig = 0;
    var k = i;
    while k < eq {
      let b = _byte_at(raw, k);
      if !_is_digit(b) {
        return _at_offset("fix: non-digit tag at offset ", i);
      }
      tag = tag * 10 + (b - _FIX_ZERO);
      ndig = ndig + 1;
      k = k + 1;
    }
    if ndig > 9 {
      return _at_offset("fix: tag out of range at offset ", i);
    }
    if tag == 0 {
      return _at_offset("fix: invalid tag 0 at offset ", i);
    }
    let value_start = eq + 1;
    let value_end = field_end;
    if field == 0 && tag != 8 {
      return "fix: first field must be tag 8 (BeginString)";
    }
    if field == 1 && tag != 9 {
      return "fix: second field must be tag 9 (BodyLength)";
    }
    if field >= 2 {
      if tag == 8 {
        return "fix: duplicate tag 8";
      }
      if tag == 9 {
        return "fix: duplicate tag 9";
      }
    }
    if tag == 8 && value_end == value_start {
      return "fix: empty BeginString";
    }
    if tag == 35 {
      seen35 = true;
      if value_end == value_start {
        return "fix: empty MsgType";
      }
    }
    m.tags.push(tag);
    m.starts.push(value_start);
    m.ends.push(value_end);
    if tag == 10 {
      if after < n {
        return _at_offset("fix: trailing bytes after checksum at offset ", after);
      }
      let bl_start: Int = m.starts[1];
      let bl_end: Int = m.ends[1];
      let declared = _parse_uint(raw, bl_start, bl_end);
      if declared < 0 {
        return "fix: BodyLength is not a non-negative integer";
      }
      let body_start = bl_end + 1;
      let actual = i - body_start;
      if declared != actual {
        return "fix: BodyLength mismatch: declared " + _int_to_str(declared) + " actual " + _int_to_str(actual);
      }
      if !seen35 {
        return "fix: missing tag 35 (MsgType)";
      }
      var checksum_val = -1;
      if value_end - value_start == 3 {
        checksum_val = _parse_uint(raw, value_start, value_end);
      }
      if checksum_val < 0 || checksum_val > 255 {
        return _at_offset("fix: invalid CheckSum at offset ", value_start);
      }
      var sum = 0;
      var q = 0;
      while q < i {
        sum = sum + _byte_at(raw, q);
        q = q + 1;
      }
      let computed = sum % 256;
      if checksum_val != computed {
        return "fix: CheckSum mismatch: declared " + _int_to_str(checksum_val) + " computed " + _int_to_str(computed);
      }
      m.body_length = declared;
      m.checksum = checksum_val;
      return "";
    }
    if soh < 0 {
      return _at_offset("fix: missing SOH terminator at offset ", i);
    }
    i = after;
    field = field + 1;
  }
  return "fix: missing tag 10 (CheckSum)";
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one in-memory FIX message.
/// Params: text - the whole message as `Str`; fields are separated by SOH
/// (0x01) and each field is `tag=value` with a decimal tag.
/// Returns: Ok(FixMessage) when the frame is valid: tag 8 (BeginString)
/// is the first field and non-empty, tag 9 (BodyLength) is the second field
/// and equals the byte count between the SOH that follows tag 9 and the start
/// of "10=", a non-empty tag 35 (MsgType) field is present, tag 10 (CheckSum)
/// is the last field and equals the sum of all bytes before "10=" modulo 256
/// written as exactly three digits. Values may be empty (except BeginString
/// and MsgType) and duplicate tags are preserved in order; a duplicate of tag
/// 8 or 9, any duplicate of tag 10 (reported as trailing bytes), a missing
/// final SOH on a non-checksum field, and every malformed tag/value shape are
/// Err with a deterministic "fix: ..." message (see SPEC.md).
/// Error case: "fix: empty message", "fix: missing SOH terminator at offset
/// N", "fix: missing '=' in field at offset N", "fix: non-digit tag at offset
/// N", "fix: invalid tag 0 at offset N", "fix: tag out of range at offset N",
/// "fix: first field must be tag 8 (BeginString)", "fix: second field must be
/// tag 9 (BodyLength)", "fix: duplicate tag 8", "fix: duplicate tag 9",
/// "fix: empty BeginString", "fix: empty MsgType", "fix: missing tag 35
/// (MsgType)", "fix: missing tag 10 (CheckSum)", "fix: trailing bytes after
/// checksum at offset N", "fix: BodyLength is not a non-negative integer",
/// "fix: BodyLength mismatch: declared N actual M", "fix: invalid CheckSum at
/// offset N", "fix: CheckSum mismatch: declared N computed M".
/// Complexity: O(text length).
pub fn fix_parse(text: Str) -> Result[FixMessage, Str] {
  if text.len() == 0 {
    return _err_fix("fix: empty message");
  }
  var m = FixMessage{
    raw: text;
    tags: Vec[Int].new();
    starts: Vec[Int].new();
    ends: Vec[Int].new();
    body_length: 0;
    checksum: 0;
  };
  let scan_err = _scan_fields(text, &mut m);
  if scan_err.len() > 0 {
    return _err_fix(scan_err);
  }
  return _ok_fix(m);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of stored fields, duplicates counted. Tags 8, 9 and 10 are stored
/// like every other field, so a minimal message (`8=`, `9=`, `35=`, `10=`)
/// has count 4.
/// Error case: none.
/// Complexity: O(1).
pub fn fix_tag_count(m: &FixMessage) -> Int {
  return m.tags.len();
}

// The byte span of stored field `i` (bounds-checked against the sibling
// vectors); "" for an out-of-range or misaligned hand-built message.
fn _value_at(m: &FixMessage, i: Int) -> Str {
  if i < 0 || i >= m.starts.len() || i >= m.ends.len() {
    return "";
  }
  let raw: Str = m.raw;
  let s: Int = m.starts[i];
  let e: Int = m.ends[i];
  return string.str_slice(raw, s, e);
}

/// First value stored under `tag` (byte-exact tag match), in wire order;
/// None when the tag is absent. Duplicate tags are preserved, so this is the
/// earliest occurrence.
/// Error case: none.
/// Complexity: O(tag count).
pub fn fix_value(m: &FixMessage, tag: Int) -> Option[Str] {
  var i = 0;
  while i < m.tags.len() {
    let t: Int = m.tags[i];
    if t == tag {
      return Some(_value_at(m, i));
    }
    i = i + 1;
  }
  return None;
}

/// Last value stored under `tag`, in wire order; None when the tag is absent.
/// For a tag that appears once this returns the same value as `fix_value`.
/// Error case: none.
/// Complexity: O(tag count).
pub fn fix_value_last(m: &FixMessage, tag: Int) -> Option[Str] {
  var i = m.tags.len() - 1;
  while i >= 0 {
    let t: Int = m.tags[i];
    if t == tag {
      return Some(_value_at(m, i));
    }
    i = i - 1;
  }
  return None;
}

/// Value of the first tag 35 (MsgType) field, or "" when no such field is
/// stored (a hand-built message). Messages from `fix_parse` always have a
/// non-empty MsgType.
/// Error case: none.
/// Complexity: O(tag count).
pub fn fix_msg_type(m: &FixMessage) -> Str {
  var i = 0;
  while i < m.tags.len() {
    let t: Int = m.tags[i];
    if t == 35 {
      return _value_at(m, i);
    }
    i = i + 1;
  }
  return "";
}

// --------------------------------------------------
//  Canonical emit
// --------------------------------------------------

/// Serialize a message canonically, recomputing tags 9 and 10.
/// Params: m - a parsed message, or a hand-built one whose `tags` / `starts`
/// / `ends` are index-aligned and whose spans lie inside `raw`.
/// Returns: Ok(text) for the canonical frame
/// `8=<value><SOH>` + `9=<body length><SOH>` + every field whose tag is not
/// 8, 9 or 10 in stored order + `10=<checksum><SOH>`. The other tag-8 fields
/// are duplicates and rejected; stored tag-9 and tag-10 fields are ignored
/// and regenerated, so stale BodyLength/CheckSum values never reach the
/// output. BodyLength is the byte length of the middle section and CheckSum
/// is the sum of every byte before "10=" modulo 256, written as exactly three
/// digits. Tag numbers are written without leading zeros; values are copied
/// byte-for-byte and must not contain 0x00 or SOH.
/// Error case: "fix: cannot emit: field vectors are not aligned", "fix:
/// cannot emit: invalid tag", "fix: cannot emit: field span out of range",
/// "fix: cannot emit: value contains a reserved byte", "fix: cannot emit:
/// duplicate tag 8", "fix: cannot emit without tag 8 (BeginString)".
/// Complexity: O(total bytes).
pub fn fix_emit(m: &FixMessage) -> Result[Str, Str] {
  let nt = m.tags.len();
  if nt != m.starts.len() || nt != m.ends.len() {
    return _err_out("fix: cannot emit: field vectors are not aligned");
  }
  let raw: Str = m.raw;
  let raw_n = raw.len();
  var begin_idx = -1;
  var i = 0;
  while i < nt {
    let t: Int = m.tags[i];
    let s: Int = m.starts[i];
    let e: Int = m.ends[i];
    if t <= 0 || t > 999999999 {
      return _err_out("fix: cannot emit: invalid tag");
    }
    if s < 0 || e < s || e > raw_n {
      return _err_out("fix: cannot emit: field span out of range");
    }
    if t == 8 {
      if begin_idx >= 0 {
        return _err_out("fix: cannot emit: duplicate tag 8");
      }
      begin_idx = i;
    }
    if t != 9 && t != 10 {
      var j = s;
      while j < e {
        let b = _byte_at(raw, j);
        if b == 0 || b == _FIX_SOH {
          return _err_out("fix: cannot emit: value contains a reserved byte");
        }
        j = j + 1;
      }
    }
    i = i + 1;
  }
  if begin_idx < 0 {
    return _err_out("fix: cannot emit without tag 8 (BeginString)");
  }
  let begin_val = _value_at(m, begin_idx);
  var out = Vec[UInt8].new();
  builder.sb_push_byte(&mut out, _FIX_CHR_8 as UInt8);
  builder.sb_push_byte(&mut out, _FIX_EQ as UInt8);
  builder.sb_push_str(&mut out, begin_val);
  builder.sb_push_byte(&mut out, _FIX_SOH as UInt8);
  // Middle section: every field except 8, 9 and 10, in stored order.
  var mid = Vec[UInt8].new();
  i = 0;
  while i < nt {
    let t: Int = m.tags[i];
    if t != 8 && t != 9 && t != 10 {
      let s: Int = m.starts[i];
      let e: Int = m.ends[i];
      builder.sb_push_int(&mut mid, t);
      builder.sb_push_byte(&mut mid, _FIX_EQ as UInt8);
      var j = s;
      while j < e {
        let b = _byte_at(raw, j);
        mid.push(b as UInt8);
        j = j + 1;
      }
      builder.sb_push_byte(&mut mid, _FIX_SOH as UInt8);
    }
    i = i + 1;
  }
  builder.sb_push_byte(&mut out, _FIX_CHR_9 as UInt8);
  builder.sb_push_byte(&mut out, _FIX_EQ as UInt8);
  builder.sb_push_int(&mut out, mid.len());
  builder.sb_push_byte(&mut out, _FIX_SOH as UInt8);
  var j2 = 0;
  while j2 < mid.len() {
    let mb: UInt8 = mid[j2];
    out.push(mb);
    j2 = j2 + 1;
  }
  var sum = 0;
  var q = 0;
  while q < out.len() {
    let ob: UInt8 = out[q];
    sum = sum + ((ob as Int) & 0xFF);
    q = q + 1;
  }
  let cs = sum % 256;
  let hundreds = cs / 100;
  let tens = (cs / 10) % 10;
  let ones = cs % 10;
  builder.sb_push_str(&mut out, "10=");
  builder.sb_push_byte(&mut out, (_FIX_ZERO + hundreds) as UInt8);
  builder.sb_push_byte(&mut out, (_FIX_ZERO + tens) as UInt8);
  builder.sb_push_byte(&mut out, (_FIX_ZERO + ones) as UInt8);
  builder.sb_push_byte(&mut out, _FIX_SOH as UInt8);
  return _ok_out(builder.sb_to_str(&out));
}
