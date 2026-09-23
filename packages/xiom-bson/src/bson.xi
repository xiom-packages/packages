// XIOM -- xiom.bson: pure-XIOM BSON document encoding and decoding
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A no-FFI BSON codec for the supported subset: int32 (0x10), int64
// (0x12), UTF-8 string (0x02), embedded document (0x03), array (0x04),
// bool (0x08) and null (0x0A). The encoder is a stack-based BsonWriter
// that reserves and patches the little-endian document length; the
// decoder is a set of flat accessors over a complete document
// (Vec[UInt8]). See SPEC.md for the byte-level format table, error
// catalog and documented limitations.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err/Some construction is confined to the tiny leaf helpers below
//     (constructing Result/Option values directly in other functions
//     miscompiles).
//   * all multi-byte little-endian extraction is arithmetic
//     (division/modulo); `& 0xFF` on values with bit 31 set miscompiles.
//   * doubles (0x01) are NOT supported: XIOM v0.61.3 has no Int<->Float64
//     bitcast intrinsic (xiom.num.float is a documented zero-returning
//     stub), so the exact IEEE-754 payload can neither be encoded nor
//     decoded without FFI. Documents containing a double are invalid.
//   * array elements are written with the caller-supplied numeric key
//     ("0", "1", ...); the writer keeps no per-array counters, so the
//     numeric-key convention is explicit at the call site.

module xiom.bson

use xiom.string;
use xiom.string.builder;
use xiom.convert;

/// Mutable BSON document builder.
/// `buf` holds the encoded bytes; `open_docs` is the stack of start
/// offsets of the documents/arrays that are still open. Fields are
/// implementation details; callers must go through the free functions
/// below.
pub type BsonWriter = {
  buf: Vec[UInt8];
  open_docs: Vec[Int];
}

// --------------------------------------------------
//  Result / Option constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Some(v) for Option[Int].
fn _some_int(v: Int) -> Option[Int] {
  return Some(v);
}

// None for Option[Int].
fn _none_int() -> Option[Int] {
  return None;
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Two lowercase hex digits for a byte value (0..255).
fn _hex2(b: Int) -> Str {
  let digits = "0123456789abcdef";
  let hi = b / 16;
  let lo = b % 16;
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

// "bson: unexpected type 0xNN" for a raw BSON type byte.
fn _unexpected(t: Int) -> Str {
  return "bson: unexpected type 0x" + _hex2(t);
}

// Byte number `k` of `v` (0 = least significant). Arithmetic only:
// `& 0xFF` on values with bit 31 set miscompiles in v0.61.3, and this
// form is exact for negative two's-complement values.
fn _byte_at(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in LITTLE-endian order.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_byte_at(v, i));
    i = i + 1;
  }
}

// Append a cstring: the bytes of `s` then the 0x00 terminator.
fn _push_cstr(out: &mut Vec[UInt8], s: Str) {
  builder.sb_push_str(out, s);
  out.push(0 as UInt8);
}

// --------------------------------------------------
//  Encoder
// --------------------------------------------------

/// Create an empty writer.
pub fn bson_writer_new() -> BsonWriter {
  return BsonWriter{ buf: Vec[UInt8].new(); open_docs: Vec[Int].new(); };
}

/// Start a top-level or embedded document: pushes the start offset and
/// reserves the 4 little-endian length bytes (patched by bson_doc_end).
pub fn bson_doc_start(w: &mut BsonWriter) {
  let start = w.buf.len();
  w.open_docs.push(start);
  _push_le(&mut w.buf, 0, 4);
}

/// Write an int32 element (type 0x10): cstring name + 4 LE bytes.
pub fn bson_element_int32(w: &mut BsonWriter, name: Str, v: Int) {
  w.buf.push(0x10 as UInt8);
  _push_cstr(&mut w.buf, name);
  _push_le(&mut w.buf, v, 4);
}

/// Write an int64 element (type 0x12): cstring name + 8 LE bytes.
pub fn bson_element_int64(w: &mut BsonWriter, name: Str, v: Int) {
  w.buf.push(0x12 as UInt8);
  _push_cstr(&mut w.buf, name);
  _push_le(&mut w.buf, v, 8);
}

/// Write a string element (type 0x02): cstring name, int32 LE byte
/// length (INCLUDING the trailing NUL), the UTF-8 bytes verbatim, NUL.
pub fn bson_element_str(w: &mut BsonWriter, name: Str, v: Str) {
  w.buf.push(0x02 as UInt8);
  _push_cstr(&mut w.buf, name);
  _push_le(&mut w.buf, string.str_len(v) + 1, 4);
  builder.sb_push_str(&mut w.buf, v);
  w.buf.push(0 as UInt8);
}

/// Write a bool element (type 0x08): cstring name + one byte 0x00/0x01.
pub fn bson_element_bool(w: &mut BsonWriter, name: Str, v: Bool) {
  w.buf.push(0x08 as UInt8);
  _push_cstr(&mut w.buf, name);
  if v {
    w.buf.push(1 as UInt8);
  } else {
    w.buf.push(0 as UInt8);
  }
}

/// Write a null element (type 0x0A): cstring name, no payload.
pub fn bson_element_null(w: &mut BsonWriter, name: Str) {
  w.buf.push(0x0A as UInt8);
  _push_cstr(&mut w.buf, name);
}

/// Start an EMBEDDED DOCUMENT element (type 0x03): type byte, cstring
/// name, then an open sub-document whose length is patched by
/// bson_element_doc_end.
///
/// NOTE: this pair is an addition beyond the minimal API list -- without
/// it the encoder could not emit 0x03 elements at all (only arrays).
pub fn bson_element_doc_start(w: &mut BsonWriter, name: Str) {
  w.buf.push(0x03 as UInt8);
  _push_cstr(&mut w.buf, name);
  bson_doc_start(w);
}

/// Close an embedded document opened by bson_element_doc_start.
pub fn bson_element_doc_end(w: &mut BsonWriter)
  requires: w.open_docs.len() > 0
{
  bson_doc_end(w);
}

/// Start an ARRAY element (type 0x04): type byte, cstring name, then an
/// open sub-document. Array entries are added with the numeric key as
/// their name ("0", "1", ...) -- BSON array semantics, explicit at the
/// call site (see the module header).
pub fn bson_element_array_start(w: &mut BsonWriter, name: Str) {
  w.buf.push(0x04 as UInt8);
  _push_cstr(&mut w.buf, name);
  bson_doc_start(w);
}

/// Close an array opened by bson_element_array_start.
pub fn bson_element_array_end(w: &mut BsonWriter)
  requires: w.open_docs.len() > 0
{
  bson_doc_end(w);
}

/// Close the innermost open document/array: appends the 0x00 terminator,
/// then patches the 4 reserved length bytes with the total size (length
/// prefix, elements and terminator included). Popping an empty stack is
/// a programming error trapped by the `requires` contract.
pub fn bson_doc_end(w: &mut BsonWriter)
  requires: w.open_docs.len() > 0
{
  w.buf.push(0 as UInt8);
  let stack_len = w.open_docs.len();
  if stack_len > 0 {
    let start = w.open_docs[stack_len - 1];
    let total = w.buf.len() - start;
    var k = 0;
    while k < 4 {
      w.buf[start + k] = _byte_at(total, k);
      k = k + 1;
    }
    w.open_docs.pop();
  }
}

/// Copy of the encoded bytes built so far.
pub fn bson_to_bytes(w: &BsonWriter) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < w.buf.len() {
    out.push(w.buf[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Decoder internals
// --------------------------------------------------

// Read 4 bytes at `pos` as a SIGNED little-endian int32.
fn _read_le_int32(data: &Vec[UInt8], pos: Int) -> Result[Int, Str] {
  if pos < 0 || pos + 4 > data.len() {
    return _err_int("bson: truncated document");
  }
  var v: Int = 0;
  var i = 3;
  while i >= 0 {
    v = v * 256 + (data[pos + i] as Int);
    i = i - 1;
  }
  if (data[pos + 3] as Int) >= 128 {
    v = v - 4294967296;
  }
  return _ok_int(v);
}

// Read 8 bytes at `pos` as a SIGNED little-endian int64. The accumulator
// arithmetic wraps to the two's-complement bit pattern for high-bit
// payloads (Int is signed 64-bit; documented in SPEC.md).
fn _read_le_int64(data: &Vec<UInt8>, pos: Int) -> Result[Int, Str] {
  if pos < 0 || pos + 8 > data.len() {
    return _err_int("bson: truncated document");
  }
  var v: Int = 0;
  var i = 7;
  while i >= 0 {
    v = v * 256 + (data[pos + i] as Int);
    i = i - 1;
  }
  return _ok_int(v);
}

// Index of the NUL terminating a cstring in [start, end), or -1.
fn _name_nul(data: &Vec<UInt8>, start: Int, end: Int) -> Int {
  var i = start;
  while i < end {
    if (data[i] as Int) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

// True when the NUL-terminated bytes in [start, nul) equal `s`.
fn _name_equals(data: &Vec<UInt8>, start: Int, nul: Int, s: Str) -> Bool {
  if nul - start != string.str_len(s) {
    return false;
  }
  var i = 0;
  while i < nul - start {
    if (data[start + i] as Int) != (string.byte_at(s, i) as Int) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Validate the value of type `t` starting at `vstart` inside a document
// whose terminator is at `end`; returns the position after the value.
// Checks lengths, terminators and bounds one level deep (nested document
// bodies are validated by _scan_body).
fn _value_end(data: &Vec<UInt8>, vstart: Int, t: Int, end: Int) -> Result[Int, Str] {
  if t == 0x10 {
    if vstart + 4 > end { return _err_int("bson: truncated document"); }
    return _ok_int(vstart + 4);
  }
  if t == 0x12 {
    if vstart + 8 > end { return _err_int("bson: truncated document"); }
    return _ok_int(vstart + 8);
  }
  if t == 0x08 {
    if vstart + 1 > end { return _err_int("bson: truncated document"); }
    return _ok_int(vstart + 1);
  }
  if t == 0x0A {
    return _ok_int(vstart);
  }
  if t == 0x02 {
    if vstart + 4 > end { return _err_int("bson: truncated document"); }
    let lr = _read_le_int32(data, vstart);
    if !lr.is_ok { return _err_int(lr.error); }
    let slen = lr.value;
    if slen < 1 { return _err_int("bson: malformed length"); }
    if vstart + 4 + slen > end { return _err_int("bson: truncated document"); }
    if (data[vstart + 4 + slen - 1] as Int) != 0 {
      return _err_int("bson: truncated document");
    }
    return _ok_int(vstart + 4 + slen);
  }
  if t == 0x03 || t == 0x04 {
    if vstart + 4 > end { return _err_int("bson: truncated document"); }
    let lr = _read_le_int32(data, vstart);
    if !lr.is_ok { return _err_int(lr.error); }
    let dlen = lr.value;
    if dlen < 5 { return _err_int("bson: malformed length"); }
    if vstart + dlen > end { return _err_int("bson: truncated document"); }
    if (data[vstart + dlen - 1] as Int) != 0 {
      return _err_int("bson: truncated document");
    }
    return _ok_int(vstart + dlen);
  }
  return _err_int(_unexpected(t));
}

// Position of the value of the element whose type byte is at `tpos`
// (just past the cstring name).
fn _value_start(data: &Vec<UInt8>, tpos: Int, end: Int) -> Result[Int, Str] {
  let nul = _name_nul(data, tpos + 1, end);
  if nul < 0 { return _err_int("bson: truncated document"); }
  return _ok_int(nul + 1);
}

// Validate the matched top-level element with type byte `t` at `pos`
// against the document terminator and return its value start.
fn _value_ready(data: &Vec<UInt8>, pos: Int, t: Int) -> Result[Int, Str] {
  let vsr = _value_start(data, pos, data.len() - 1);
  if !vsr.is_ok { return _err_int(vsr.error); }
  let vr = _value_end(data, vsr.value, t, data.len() - 1);
  if !vr.is_ok { return _err_int(vr.error); }
  return _ok_int(vsr.value);
}

// Parse one element with its type byte at `pos` (name + value) inside a
// document whose terminator is at `end`; returns the position after it.
fn _element_end(data: &Vec<UInt8>, pos: Int, end: Int) -> Result[Int, Str] {
  if pos >= end { return _err_int("bson: truncated document"); }
  let t = data[pos] as Int;
  let nul = _name_nul(data, pos + 1, end);
  if nul < 0 { return _err_int("bson: truncated document"); }
  return _value_end(data, nul + 1, t, end);
}

// Find the first element named `name` in the document body [start, end)
// (start = first element position, end = terminator index). Returns the
// type-byte position of the match, or an Err with the failure reason.
fn _find_element(data: &Vec<UInt8>, start: Int, end: Int, name: Str) -> Result[Int, Str] {
  var pos = start;
  while pos < end {
    let t = data[pos] as Int;
    let nul = _name_nul(data, pos + 1, end);
    if nul < 0 { return _err_int("bson: truncated document"); }
    if _name_equals(data, pos + 1, nul, name) {
      return _ok_int(pos);
    }
    let vr = _value_end(data, nul + 1, t, end);
    if !vr.is_ok { return _err_int(vr.error); }
    pos = vr.value;
  }
  if pos != end { return _err_int("bson: truncated document"); }
  return _err_int("bson: field not found: " + name);
}

// Validate a document's leading length field and terminator; returns the
// terminator index (declared length - 1) or the failure reason.
fn _doc_end(data: &Vec<UInt8>) -> Result[Int, Str] {
  if data.len() < 5 {
    return _err_int("bson: truncated document");
  }
  let lr = _read_le_int32(data, 0);
  if !lr.is_ok { return _err_int(lr.error); }
  let l = lr.value;
  if l < 5 || l != data.len() {
    return _err_int("bson: malformed length");
  }
  if (data[l - 1] as Int) != 0 {
    return _err_int("bson: truncated document");
  }
  return _ok_int(l - 1);
}

// Find a top-level element of a complete document.
fn _find_top(data: &Vec<UInt8>, name: Str) -> Result[Int, Str] {
  let er = _doc_end(data);
  if !er.is_ok { return _err_int(er.error); }
  return _find_element(data, 4, er.value, name);
}

// Count the elements of a document body [start, end).
fn _count_body(data: &Vec<UInt8>, start: Int, end: Int) -> Result[Int, Str] {
  var count = 0;
  var pos = start;
  while pos < end {
    let er = _element_end(data, pos, end);
    if !er.is_ok { return _err_int(er.error); }
    pos = er.value;
    count = count + 1;
  }
  if pos != end { return _err_int("bson: truncated document"); }
  return _ok_int(count);
}

// Recursively validate a document body [start, end): every element is
// well-formed, every nested document/array is itself valid, and the walk
// ends exactly at the terminator. `depth` caps nesting at 100 levels.
fn _scan_body(data: &Vec<UInt8>, start: Int, end: Int, depth: Int) -> Bool {
  var pos = start;
  while pos < end {
    let t = data[pos] as Int;
    if t == 0x03 || t == 0x04 {
      if depth >= 100 { return false; }
      let nul = _name_nul(data, pos + 1, end);
      if nul < 0 { return false; }
      let vstart = nul + 1;
      if vstart + 4 > end { return false; }
      let lr = _read_le_int32(data, vstart);
      if !lr.is_ok { return false; }
      let dlen = lr.value;
      if dlen < 5 { return false; }
      if vstart + dlen > end { return false; }
      if (data[vstart + dlen - 1] as Int) != 0 { return false; }
      if !_scan_body(data, vstart + 4, vstart + dlen - 1, depth + 1) { return false; }
      pos = vstart + dlen;
    } else {
      let er = _element_end(data, pos, end);
      if !er.is_ok { return false; }
      pos = er.value;
    }
  }
  return pos == end;
}

// Find the type-byte position of array element `index` inside the array
// (0x04) element named `name`; the array sub-document, the numeric key
// lookup and the element's value are all validated on the way.
fn _array_find(data: &Vec<UInt8>, name: Str, index: Int) -> Result[Int, Str] {
  let fr = _find_top(data, name);
  if !fr.is_ok { return _err_int(fr.error); }
  let t = data[fr.value] as Int;
  if t != 0x04 { return _err_int(_unexpected(t)); }
  let ar = _value_ready(data, fr.value, t);
  if !ar.is_ok { return _err_int(ar.error); }
  let avs = ar.value;
  let lr = _read_le_int32(data, avs);
  if !lr.is_ok { return _err_int(lr.error); }
  let sub_end = avs + lr.value - 1;
  let key = convert.int_to_string(index);
  let er = _find_element(data, avs + 4, sub_end, key);
  if !er.is_ok { return _err_int(er.error); }
  let et = data[er.value] as Int;
  let evsr = _value_start(data, er.value, sub_end);
  if !evsr.is_ok { return _err_int(evsr.error); }
  let evr = _value_end(data, evsr.value, et, sub_end);
  if !evr.is_ok { return _err_int(evr.error); }
  return _ok_int(er.value);
}

// Copy the string payload of the element whose VALUE starts at `vstart`
// (the element was validated by a previous walk).
fn _get_str_at(data: &Vec<UInt8>, vstart: Int) -> Result[Str, Str] {
  let lr = _read_le_int32(data, vstart);
  if !lr.is_ok { return _err_str(lr.error); }
  let slen = lr.value;
  if slen < 1 { return _err_str("bson: malformed length"); }
  let start = vstart + 4;
  let stop = start + slen - 1;
  if stop + 1 > data.len() { return _err_str("bson: truncated document"); }
  var sb = Vec[UInt8].new();
  var i = start;
  while i < stop {
    sb.push(data[i]);
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&sb));
}

// --------------------------------------------------
//  Decoder (flat accessors over a complete document)
// --------------------------------------------------

/// Structural validity walk over a complete document: the leading length
/// must equal the buffer length, the terminator must be present, and
/// every element (including nested document/array bodies, up to 100
/// levels) must use a supported type with sound lengths and bounds.
pub fn bson_is_valid(data: &Vec[UInt8]) -> Bool {
  let er = _doc_end(data);
  if !er.is_ok { return false; }
  return _scan_body(data, 4, er.value, 0);
}

/// Top-level element names in document order. On a malformed document
/// the result is a one-element vector containing the empty string (the
/// documented malformed sentinel); a valid empty document yields an
/// empty vector.
pub fn bson_keys(data: &Vec[UInt8]) -> Vec[Str] {
  var keys = Vec[Str].new();
  let er = _doc_end(data);
  if !er.is_ok {
    keys.push("");
    return keys;
  }
  let end = er.value;
  var pos = 4;
  while pos < end {
    let t = data[pos] as Int;
    let nul = _name_nul(data, pos + 1, end);
    if nul < 0 {
      return _keys_malformed();
    }
    var nb = Vec[UInt8].new();
    var i = pos + 1;
    while i < nul {
      nb.push(data[i]);
      i = i + 1;
    }
    keys.push(builder.sb_to_str(&nb));
    let vr = _value_end(data, nul + 1, t, end);
    if !vr.is_ok {
      return _keys_malformed();
    }
    pos = vr.value;
  }
  if pos != end {
    return _keys_malformed();
  }
  return keys;
}

// Malformed-document sentinel for bson_keys: [""].
fn _keys_malformed() -> Vec[Str] {
  var keys = Vec[Str].new();
  keys.push("");
  return keys;
}

/// BSON type byte of the first top-level element named `name`
/// (0x10 int32, 0x12 int64, 0x02 str, 0x03 doc, 0x04 array, 0x08 bool,
/// 0x0A null), or None when the document is malformed or the field is
/// absent.
pub fn bson_type_of(data: &Vec<UInt8>, name: Str) -> Option[Int] {
  let fr = _find_top(data, name);
  if !fr.is_ok { return _none_int(); }
  return _some_int(data[fr.value] as Int);
}

/// True when a top-level element named `name` exists in a structurally
/// walkable document.
pub fn bson_has(data: &Vec<UInt8>, name: Str) -> Bool {
  let fr = _find_top(data, name);
  return fr.is_ok;
}

/// Value of the int32 (0x10) element named `name`.
/// Err("bson: unexpected type 0xNN") on a different type.
pub fn bson_get_int32(data: &Vec<UInt8>, name: Str) -> Result[Int, Str] {
  let fr = _find_top(data, name);
  if !fr.is_ok { return _err_int(fr.error); }
  let t = data[fr.value] as Int;
  if t != 0x10 { return _err_int(_unexpected(t)); }
  let vr = _value_ready(data, fr.value, t);
  if !vr.is_ok { return _err_int(vr.error); }
  return _read_le_int32(data, vr.value);
}

/// Value of the int64 (0x12) element named `name`.
/// Err("bson: unexpected type 0xNN") on a different type.
pub fn bson_get_int64(data: &Vec<UInt8>, name: Str) -> Result[Int, Str] {
  let fr = _find_top(data, name);
  if !fr.is_ok { return _err_int(fr.error); }
  let t = data[fr.value] as Int;
  if t != 0x12 { return _err_int(_unexpected(t)); }
  let vr = _value_ready(data, fr.value, t);
  if !vr.is_ok { return _err_int(vr.error); }
  return _read_le_int64(data, vr.value);
}

/// Value of the string (0x02) element named `name`; the UTF-8 payload
/// bytes are copied verbatim (no validation).
/// Err("bson: unexpected type 0xNN") on a different type.
pub fn bson_get_str(data: &Vec<UInt8>, name: Str) -> Result[Str, Str] {
  let fr = _find_top(data, name);
  if !fr.is_ok { return _err_str(fr.error); }
  let t = data[fr.value] as Int;
  if t != 0x02 { return _err_str(_unexpected(t)); }
  let vr = _value_ready(data, fr.value, t);
  if !vr.is_ok { return _err_str(vr.error); }
  return _get_str_at(data, vr.value);
}

/// Value of the bool (0x08) element named `name`; any non-zero payload
/// byte reads as true.
/// Err("bson: unexpected type 0xNN") on a different type.
pub fn bson_get_bool(data: &Vec<UInt8>, name: Str) -> Result[Bool, Str] {
  let fr = _find_top(data, name);
  if !fr.is_ok { return _err_bool(fr.error); }
  let t = data[fr.value] as Int;
  if t != 0x08 { return _err_bool(_unexpected(t)); }
  let vr = _value_ready(data, fr.value, t);
  if !vr.is_ok { return _err_bool(vr.error); }
  if (data[vr.value] as Int) != 0 { return _ok_bool(true); }
  return _ok_bool(false);
}

/// Bytes of the embedded document (0x03) element named `name`, copied
/// into a fresh Vec[UInt8] (the returned bytes form a complete document
/// that the other accessors accept).
/// Err("bson: unexpected type 0xNN") on a different type.
pub fn bson_get_document(data: &Vec<UInt8>, name: Str) -> Result[Vec[UInt8], Str] {
  let fr = _find_top(data, name);
  if !fr.is_ok { return _err_bytes(fr.error); }
  let t = data[fr.value] as Int;
  if t != 0x03 { return _err_bytes(_unexpected(t)); }
  let vr = _value_ready(data, fr.value, t);
  if !vr.is_ok { return _err_bytes(vr.error); }
  let vs = vr.value;
  let lr = _read_le_int32(data, vs);
  if !lr.is_ok { return _err_bytes(lr.error); }
  var out = Vec[UInt8].new();
  var i = vs;
  let stop = vs + lr.value;
  while i < stop {
    out.push(data[i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Number of elements of the array (0x04) element named `name`.
/// Err("bson: unexpected type 0xNN") on a different type.
pub fn bson_get_array_len(data: &Vec<UInt8>, name: Str) -> Result[Int, Str] {
  let fr = _find_top(data, name);
  if !fr.is_ok { return _err_int(fr.error); }
  let t = data[fr.value] as Int;
  if t != 0x04 { return _err_int(_unexpected(t)); }
  let ar = _value_ready(data, fr.value, t);
  if !ar.is_ok { return _err_int(ar.error); }
  let lr = _read_le_int32(data, ar.value);
  if !lr.is_ok { return _err_int(lr.error); }
  return _count_body(data, ar.value + 4, ar.value + lr.value - 1);
}

/// String (0x02) value of array element `index` inside the array (0x04)
/// element named `name`. An index outside the array is reported as
/// Err("bson: field not found: <index>") because BSON array keys are the
/// decimal index strings.
pub fn bson_get_array_str(data: &Vec<UInt8>, name: Str, index: Int) -> Result[Str, Str] {
  let ar = _array_find(data, name, index);
  if !ar.is_ok { return _err_str(ar.error); }
  let t = data[ar.value] as Int;
  if t != 0x02 { return _err_str(_unexpected(t)); }
  let vsr = _value_start(data, ar.value, data.len() - 1);
  if !vsr.is_ok { return _err_str(vsr.error); }
  return _get_str_at(data, vsr.value);
}

/// int32 (0x10) value of array element `index` inside the array (0x04)
/// element named `name`. An index outside the array is reported as
/// Err("bson: field not found: <index>").
pub fn bson_get_array_int32(data: &Vec<UInt8>, name: Str, index: Int) -> Result[Int, Str] {
  let ar = _array_find(data, name, index);
  if !ar.is_ok { return _err_int(ar.error); }
  let t = data[ar.value] as Int;
  if t != 0x10 { return _err_int(_unexpected(t)); }
  let vsr = _value_start(data, ar.value, data.len() - 1);
  if !vsr.is_ok { return _err_int(vsr.error); }
  return _read_le_int32(data, vsr.value);
}
