// XIOM -- xiom.ris: RIS bibliography parser and canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one bibliography is four parallel vectors. Records own slices of a
// shared flat field pool: record r owns field_tags[field_starts[r] ..
// field_starts[r] + field_counts[r]] (and the same slice of field_values).
// Vec[StructType] is unsupported in this compiler, so the document is
// deliberately flat instead of a tree of record structs. Every parsed record
// starts with its TY field, stored like any other field.
//
// Subset: RIS records from `TY  - TYPE` to `ER  -`, tag lines with the exact
// `XX  - value` prefix (two tag characters, two spaces, hyphen, space),
// continuation lines appended to the previous value with one space, unknown
// tags preserved, blank lines between records, CRLF/LF normalization.
// Errors: Err("ris: ...") for a missing TY, a missing ER, a malformed tag
// line, text before the first TY, a tag that is not two characters and a
// duplicate ER. See SPEC.md for the exact grammar, error catalog and test
// plan.
//
// Language notes (XIOM v0.61.3): free functions only; Str values read from
// Vec[Str] elements are compared through str_compare after binding a typed
// local (BUG 17: `==` on such elements lowers to a pointer comparison);
// every byte read goes through _ris_byte_at, which widens with
// `(b as Int) & 0xFF` (un-masked UInt8 widenings and raw byte comparisons
// miscompile); Ok/Err values for Result[RisDoc, Str] are constructed only in
// the leaf helpers below; `&mut` is passed explicitly at every call site.

module xiom.ris

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(d) for Result[RisDoc, Str].
fn _ris_ok_doc(d: RisDoc) -> Result[RisDoc, Str] {
  return Ok(d);
}

// Err("ris: " + m + " at " + line + ": " + detail) for Result[RisDoc, Str].
fn _ris_err_at(m: Str, line: Int, detail: Str) -> Result[RisDoc, Str] {
  return Err("ris: " + m + " at " + int_to_string(line) + ": " + detail);
}

// Err("ris: " + m + " at " + line) for Result[RisDoc, Str].
fn _ris_err_line(m: Str, line: Int) -> Result[RisDoc, Str] {
  return Err("ris: " + m + " at " + int_to_string(line));
}

// Err("ris: " + m) for Result[RisDoc, Str].
fn _ris_err(m: Str) -> Result[RisDoc, Str] {
  return Err("ris: " + m);
}

// --------------------------------------------------
//  Byte constants (Int space, see _ris_byte_at)
// --------------------------------------------------

const _RIS_TAB: Int = 9;
const _RIS_LF: Int = 10;
const _RIS_CR: Int = 13;
const _RIS_SPACE: Int = 32;
const _RIS_HYPHEN: Int = 45;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// Parsed RIS bibliography. Record r owns the field pool slice
/// field_tags[field_starts[r] .. field_starts[r] + field_counts[r]] (and the
/// same slice of field_values). Tags and values are stored in document order;
/// values are trimmed. Every record produced by ris_parse has at least one
/// field and its first field is its TY line. The fields are public, but a
/// document should be built with ris_parse: ris_emit relies on the TY-first
/// invariant for every record.
pub type RisDoc = {
  field_starts: Vec[Int];
  field_counts: Vec[Int];
  field_tags: Vec[Str];
  field_values: Vec[Str];
}

// --------------------------------------------------
//  Byte and string helpers
// --------------------------------------------------

// Byte i of `s`, widened to 0..255. Every byte read in this module goes
// through here (see the module header).
fn _ris_byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for a tag byte: A-Z, a-z, 0-9.
fn _ris_is_tag_byte(b: Int) -> Bool {
  if b >= 65 && b <= 90 { return true; }
  if b >= 97 && b <= 122 { return true; }
  return b >= 48 && b <= 57;
}

// True when `a` and `b` are byte-equal (BUG 17: never `==` on Str).
fn _ris_streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Line scanning helpers
// --------------------------------------------------

// Byte length of the leading run of `line` bytes that are neither SPACE nor
// TAB. The head is the tag candidate of a tag line; an indented line has a
// head of length 0 and is never a tag line.
fn _ris_head_len(line: Str) -> Int {
  let n = line.len();
  var h = 0;
  while h < n {
    let b = _ris_byte_at(line, h);
    if b == _RIS_SPACE || b == _RIS_TAB {
      break;
    }
    h = h + 1;
  }
  return h;
}

// Index just past the tag delimiter that follows a head of `hl` bytes, or -1
// when the delimiter is absent. Two shapes are accepted: `XX  - value`
// (returns the index of the first value byte) and the end-of-line form
// `XX  -` (returns line.len(), so the value is empty).
fn _ris_value_start(line: Str, hl: Int) -> Int {
  let n = line.len();
  if hl + 4 <= n && _ris_byte_at(line, hl) == _RIS_SPACE && _ris_byte_at(line, hl + 1) == _RIS_SPACE && _ris_byte_at(line, hl + 2) == _RIS_HYPHEN && _ris_byte_at(line, hl + 3) == _RIS_SPACE {
    return hl + 4;
  }
  if hl + 3 == n && _ris_byte_at(line, hl) == _RIS_SPACE && _ris_byte_at(line, hl + 1) == _RIS_SPACE && _ris_byte_at(line, hl + 2) == _RIS_HYPHEN {
    return n;
  }
  return -1;
}

// At most 24 leading bytes of `line`, for error messages.
fn _ris_snippet(line: Str) -> Str {
  let n = line.len();
  if n <= 24 {
    return line;
  }
  return string.str_slice(line, 0, 24);
}

// Append one pending field (tag, value) to the pools. See ris_parse.
fn _ris_flush(d: &mut RisDoc, tag: Str, value: Str) {
  d.field_tags.push(tag);
  d.field_values.push(value);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse a whole RIS bibliography.
/// Params: text - the complete RIS source.
/// Returns: Ok(RisDoc) for valid input, including empty or whitespace-only
/// text; every record starts with its TY field and ends at its ER line, and
/// fields keep document order.
/// Error case: Err with a "ris: ..." message on the first error in document
/// order (missing TY, missing ER, malformed tag line, text before the first
/// TY, a tag that is not two characters, or a duplicate ER; see SPEC.md
/// section 6).
/// Complexity: O(total input length).
pub fn ris_parse(text: Str) -> Result[RisDoc, Str] {
  var doc = RisDoc{
    field_starts: Vec[Int].new();
    field_counts: Vec[Int].new();
    field_tags: Vec[Str].new();
    field_values: Vec[Str].new();
  };
  let n = text.len();
  var i = 0;
  var line_no = 0;
  var in_record = false;
  var completed = 0;
  var rec_start = 0;
  var rec_count = 0;
  var pending = false;
  var pending_tag = "";
  var pending_value = "";
  while i <= n {
    var e = i;
    while e < n && _ris_byte_at(text, e) != _RIS_LF {
      e = e + 1;
    }
    var le = e;
    if le > i && _ris_byte_at(text, le - 1) == _RIS_CR {
      le = le - 1;
    }
    let line = string.str_slice(text, i, le);
    line_no = line_no + 1;
    if string.str_trim(line).len() > 0 {
      let hl = _ris_head_len(line);
      var vs = -1;
      if hl > 0 {
        vs = _ris_value_start(line, hl);
      }
      if vs >= 0 {
        if hl != 2 {
          return _ris_err_at("tag not 2 chars", line_no, _ris_snippet(string.str_slice(line, 0, hl)));
        }
        if !_ris_is_tag_byte(_ris_byte_at(line, 0)) || !_ris_is_tag_byte(_ris_byte_at(line, 1)) {
          return _ris_err_at("malformed tag line", line_no, _ris_snippet(line));
        }
        let tag = string.str_slice(line, 0, 2);
        let value = string.str_trim(string.str_slice(line, vs, line.len()));
        if in_record {
          if _ris_streq(tag, "ER") {
            _ris_flush(&mut doc, pending_tag, pending_value);
            rec_count = rec_count + 1;
            doc.field_starts.push(rec_start);
            doc.field_counts.push(rec_count);
            in_record = false;
            completed = completed + 1;
            pending = false;
          } elif _ris_streq(tag, "TY") {
            return _ris_err_line("missing ER", line_no);
          } else {
            if pending {
              _ris_flush(&mut doc, pending_tag, pending_value);
              rec_count = rec_count + 1;
            }
            pending_tag = tag;
            pending_value = value;
            pending = true;
          }
        } else {
          if _ris_streq(tag, "TY") {
            in_record = true;
            rec_start = doc.field_tags.len();
            rec_count = 0;
            pending_tag = tag;
            pending_value = value;
            pending = true;
          } elif _ris_streq(tag, "ER") {
            if completed > 0 {
              return _ris_err_line("duplicate ER", line_no);
            }
            return _ris_err_at("missing TY", line_no, tag);
          } else {
            return _ris_err_at("missing TY", line_no, tag);
          }
        }
      } else {
        if in_record {
          pending_value = string.str_trim(pending_value + " " + string.str_trim(line));
        } else {
          return _ris_err_at("text before first TY", line_no, _ris_snippet(line));
        }
      }
    }
    if e >= n {
      i = n + 1;
    } else {
      i = e + 1;
    }
  }
  if in_record {
    return _ris_err("missing ER");
  }
  return _ris_ok_doc(doc);
}

/// Number of records in the bibliography.
/// Params: d - the parsed document.
/// Returns: the record count; 0 for an empty document.
/// Error case: none.
/// Complexity: O(1).
pub fn ris_record_count(d: &RisDoc) -> Int {
  return d.field_starts.len();
}

/// Number of fields in record `r`.
/// Params: d - the parsed document; r - the zero-based record index.
/// Returns: the field count; 0 when `r` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn ris_field_count(d: &RisDoc, r: Int) -> Int {
  if r < 0 || r >= d.field_counts.len() { return 0; }
  let c: Int = d.field_counts[r];
  return c;
}

/// Tag of field `j` in record `r`, as written (case-sensitive).
/// Params: d - the parsed document; r - the record index; j - the zero-based
/// field index within the record.
/// Returns: the two-character tag; "" when `r` or `j` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn ris_field_tag(d: &RisDoc, r: Int, j: Int) -> Str {
  if r < 0 || r >= d.field_starts.len() { return ""; }
  let start: Int = d.field_starts[r];
  let count: Int = d.field_counts[r];
  if j < 0 || j >= count { return ""; }
  let t: Str = d.field_tags[start + j];
  return t;
}

/// Trimmed value of field `j` in record `r`.
/// Params: d - the parsed document; r - the record index; j - the zero-based
/// field index within the record.
/// Returns: the value; "" when `r` or `j` is out of range or the value is
/// empty.
/// Error case: none.
/// Complexity: O(1).
pub fn ris_field_value(d: &RisDoc, r: Int, j: Int) -> Str {
  if r < 0 || r >= d.field_starts.len() { return ""; }
  let start: Int = d.field_starts[r];
  let count: Int = d.field_counts[r];
  if j < 0 || j >= count { return ""; }
  let v: Str = d.field_values[start + j];
  return v;
}

/// Value of the first field with tag `tag` in record `r`.
/// Params: d - the parsed document; r - the record index; tag - the exact,
/// case-sensitive two-character tag to look up.
/// Returns: Some(value) for the first field whose tag is byte-equal to `tag`
/// (document order), so when a tag repeats the first occurrence wins; None
/// when the record is out of range or no field has the tag.
/// Error case: none.
/// Complexity: O(fields of record r).
pub fn ris_get_field(d: &RisDoc, r: Int, tag: Str) -> Option[Str] {
  if r < 0 || r >= d.field_starts.len() { return None; }
  let start: Int = d.field_starts[r];
  let count: Int = d.field_counts[r];
  var j = 0;
  while j < count {
    let have: Str = d.field_tags[start + j];
    if compare.str_compare(have, tag) == 0 {
      let v: Str = d.field_values[start + j];
      return Some(v);
    }
    j = j + 1;
  }
  return None;
}

/// Render the document as canonical RIS text: for every record its fields in
/// document order (the first one is its TY line), each as `TAG  - value` plus
/// LF, then one `ER  - ` terminator line. Blank lines, CRLF endings and
/// continuation lines are not reproduced: layout is canonicalized, the data
/// is not. The output always re-parses, so ris_parse(ris_emit(d)) preserves
/// every record and field, including empty and unknown-tag fields.
/// Params: d - the parsed document.
/// Returns: the canonical text; "" for an empty document.
/// Error case: none.
/// Complexity: O(total emitted length).
pub fn ris_emit(d: &RisDoc) -> Str {
  var out = "";
  var r = 0;
  while r < d.field_starts.len() {
    let start: Int = d.field_starts[r];
    let count: Int = d.field_counts[r];
    var j = 0;
    while j < count {
      let tag: Str = d.field_tags[start + j];
      let value: Str = d.field_values[start + j];
      out = out + tag + "  - " + value + "\n";
      j = j + 1;
    }
    out = out + "ER  - \n";
    r = r + 1;
  }
  return out;
}
