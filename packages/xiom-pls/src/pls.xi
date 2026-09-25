// XIOM -- xiom.pls: PLS playlist parsing and canonical emitting
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, in-memory Str only: no FFI, no file I/O, no file existence or
// URL checks, no playback, and no semantics for extended PLS keys. The codec
// covers the documented subset of the PLS playlist format:
//
//   document = *line
//   line     = ws* ( section / pair / blank )
//   section  = "[" ws* name ws* "]"
//   pair     = key ws* "=" ws* value
//   key      = "Version" / "NumberOfEntries" / indexed / unknown
//   indexed  = ( "File" / "Title" / "Length" ) 1*18DIGIT
//   value    = *( byte except LF )
//   ws       = SP | TAB
//
// The `[playlist]` header is optional; any other section name is rejected.
// Keys are matched case-insensitively. file*/title*/length*-prefixed keys are
// reserved and must carry a decimal index; every other key is preserved in
// document order as an unknown key. The declared NumberOfEntries, when
// present, bounds every index; otherwise the entry count is the highest index
// seen. Every index 1..count must have a non-empty FileN. LengthN is either
// an explicit -1 (documented as unknown / live stream) or a non-negative
// whole number of seconds.
//
// Model: entries are flat and index-aligned. `files`, `titles` and `lengths`
// all have the entry count as length. Entry i (1-based, as in FileN) is
// files[i - 1] with title titles[i - 1] ("" when TitleN is absent) and length
// lengths[i - 1] (-1 when LengthN is absent or explicitly -1). Unknown keys
// live in `unknown_keys` / `unknown_values` in document order, duplicates
// included. Vec[StructType] is unsupported in this compiler, hence parallel
// Vecs instead of a list of entry structs.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Ok/Err for Result[Pls, Str] are constructed only in the leaf helpers
//     _ok_pls/_err_pls; the Pls literal itself is built only by _make_pls.
//   * Every input byte is read through _byte() as an Int, so no UInt8
//     constant >= 128 is ever involved in a comparison.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); Vec element reads always bind a typed local first.
//   * Parsing is if/elif/while only (no match, no lambdas), and every &mut
//     Vec parameter gets an explicit &mut at the call site.
//   * Str values are NUL-terminated C strings, so an embedded 0x00 byte is
//     unrepresentable in the values pushed into the builder; sb_to_str can
//     never abort on this module's output.
//
// See SPEC.md for the grammar, decisions, error catalog, round-trip rules
// and test plan.

module xiom.pls

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Byte constants (Int, see the module header)
// --------------------------------------------------

const _LF: Int = 10;
const _CR: Int = 13;
const _MINUS: Int = 45;
const _ZERO: Int = 48;
const _ONE: Int = 49;
const _NINE: Int = 57;
const _EQ: Int = 61;
const _LBRACKET: Int = 91;
const _RBRACKET: Int = 93;
const _MAX_DIGITS: Int = 18;
const _MAX_ENTRIES: Int = 1000000;

// Indexed-key kinds.
const _KIND_FILE: Int = 0;
const _KIND_TITLE: Int = 1;
const _KIND_LENGTH: Int = 2;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed PLS playlist. `files`, `titles` and `lengths` are index-aligned
/// and all have the entry count as length; entry i is 1-based (as in FileN)
/// and occupies position i - 1. `titles[i]` is "" when TitleN was absent;
/// `lengths[i]` is -1 when LengthN was absent or explicitly -1 (unknown /
/// live stream). `unknown_keys` / `unknown_values` hold unrecognized keys in
/// document order, duplicates included.
pub type Pls = {
  has_header: Bool;
  files: Vec[Str];
  titles: Vec[Str];
  lengths: Vec[Int];
  unknown_keys: Vec[Str];
  unknown_values: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// The one place a Pls value is assembled from the parallel Vecs.
fn _make_pls(has_header: Bool, files: Vec[Str], titles: Vec[Str],
             lengths: Vec[Int], unknown_keys: Vec[Str],
             unknown_values: Vec[Str]) -> Pls {
  return Pls{
    has_header: has_header;
    files: files;
    titles: titles;
    lengths: lengths;
    unknown_keys: unknown_keys;
    unknown_values: unknown_values;
  };
}

// Ok(p) for Result[Pls, Str].
fn _ok_pls(p: Pls) -> Result[Pls, Str] {
  return Ok(p);
}

// Err(m) for Result[Pls, Str].
fn _err_pls(m: Str) -> Result[Pls, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal text helpers
// --------------------------------------------------

// Byte `pos` of `s` as an Int (0..255). Callers guarantee the bounds.
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// Split `text` into lines on LF. A CR immediately before an LF is dropped,
// and one trailing CR at the very end of an unterminated final line is
// dropped too, so CRLF documents produce the same lines as LF documents and
// no line ever ends with CR. A trailing LF does not produce a final empty
// line. A lone CR elsewhere stays inside the line.
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

// Index of the first byte equal to `want` in `s`, or -1 when absent.
fn _find_byte(s: Str, want: Int) -> Int {
  let len = s.len();
  var i = 0;
  while i < len {
    if _byte(s, i) == want {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// ASCII-lowercase copy of `s` (A..Z only; every other byte is copied). PLS
// key matching is case-insensitive; keys are short and byte-wise lowering
// keeps non-ASCII bytes verbatim.
fn _lower_ascii(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if b >= 65 && b <= 90 {
      out.push((b + 32) as UInt8);
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Parse 1..18 ASCII digits as a non-negative Int; -1 when the text is empty,
// longer, or contains a non-digit. The 18-digit cap keeps the accumulation
// below Int range, so the result is exact.
fn _parse_uint(s: Str) -> Int {
  let n = s.len();
  if n == 0 { return -1; }
  if n > _MAX_DIGITS { return -1; }
  var v = 0;
  var i = 0;
  while i < n {
    let c = _byte(s, i);
    if c < _ZERO || c > _NINE { return -1; }
    v = v * 10 + (c - _ZERO);
    i = i + 1;
  }
  return v;
}

// Parse a Length value: exactly "-1" returns -1 (unknown / live stream) and
// 1..18 ASCII digits return the non-negative seconds. Anything else returns
// -2, which is never a valid length.
fn _parse_length(s: Str) -> Int {
  if s.len() == 2 {
    if _byte(s, 0) == _MINUS && _byte(s, 1) == _ONE { return -1; }
  }
  let v = _parse_uint(s);
  if v < 0 { return -2; }
  return v;
}

// Kind of an ASCII-lowercased key that is neither "version" nor
// "numberofentries": _KIND_FILE/_KIND_TITLE/_KIND_LENGTH when the key begins
// with that base name (its suffix must then be an index) and -1 for unknown
// keys. The file*/title*/length* namespaces are reserved by design.
fn _indexed_kind(lkey: Str) -> Int {
  let n = lkey.len();
  if n >= 4 && string.str_starts_with(lkey, "file") { return _KIND_FILE; }
  if n >= 5 && string.str_starts_with(lkey, "title") { return _KIND_TITLE; }
  if n >= 6 && string.str_starts_with(lkey, "length") { return _KIND_LENGTH; }
  return -1;
}

// Length of the base name of `kind`: "file" = 4, "title" = 5, "length" = 6.
fn _indexed_base(kind: Int) -> Int {
  if kind == _KIND_FILE { return 4; }
  if kind == _KIND_TITLE { return 5; }
  return 6;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory PLS document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(Pls) for a valid document (including an empty one).
/// Decisions (full statement in SPEC.md):
///   * Blank and whitespace-only lines are skipped. Every other line is
///     trimmed of SP/TAB, then classified.
///   * A line starting with "[" must be a well-formed section header: "["
///     name "]". The only accepted name is "playlist" (case-insensitive);
///     any other name is Err("pls: unknown section: ..."). The header is
///     optional and decorative: keys are interpreted the same before and
///     after it, and repeated headers are accepted.
///   * Keys and values are matched/trimmed case-insensitively and per line:
///     key = trimmed text before the first "=", value = trimmed text after
///     it. A line without "=" or with an empty key is an error.
///   * "Version" is optional; when present its value must be 2 (18-digit
///     non-negative integer; leading zeros allowed). "NumberOfEntries" is
///     optional; when present it must be a non-negative integer <= 1000000
///     and it bounds every indexed key.
///   * A key whose lowercase form starts with "file", "title" or "length" is
///     an indexed key and MUST continue with 1..18 ASCII digits forming an
///     index >= 1 (leading zeros allowed); otherwise it is
///     Err("pls: bad index in key: ..."). Exactly "file"/"title"/"length"
///     with no digits is therefore also an error.
///   * Entry count: the declared NumberOfEntries when present, else the
///     highest index seen (0 when there are no indexed keys). Every index
///     1..count must have a non-empty FileN, else
///     Err("pls: missing File<i>"). TitleN is optional ("" when absent);
///     LengthN is optional and -1 or non-negative seconds ("-1" and absence
///     are equivalent).
///   * Duplicate keys, including duplicate NumberOfEntries and Version, use
///     last-wins semantics. Unknown keys are preserved in document order.
/// Errors: "pls: ..." messages; see SPEC.md for the catalog.
/// Complexity: O(input length) plus O(entry count + indexed key count).
pub fn pls_parse(text: Str) -> Result[Pls, Str] {
  var has_header = false;
  var declared = -1;
  var rec_kind = Vec[Int].new();
  var rec_index = Vec[Int].new();
  var rec_num = Vec[Int].new();
  var rec_key = Vec[Str].new();
  var rec_value = Vec[Str].new();
  var unknown_keys = Vec[Str].new();
  var unknown_values = Vec[Str].new();
  let lines = _split_lines(text);
  let line_count = lines.len();
  var li = 0;
  while li < line_count {
    let raw: Str = lines[li];
    let line = string.str_trim(raw);
    let n = line.len();
    if n > 0 {
      let b0 = _byte(line, 0);
      if b0 == _LBRACKET {
        if _byte(line, n - 1) != _RBRACKET {
          return _err_pls("pls: malformed section header: " + line);
        }
        let name = string.str_trim(string.str_slice(line, 1, n - 1));
        if name.len() == 0 {
          return _err_pls("pls: malformed section header: " + line);
        }
        let lname = _lower_ascii(name);
        if compare.str_compare(lname, "playlist") == 0 {
          has_header = true;
        } else {
          return _err_pls("pls: unknown section: " + line);
        }
      } else {
        let eq = _find_byte(line, _EQ);
        if eq < 0 {
          return _err_pls("pls: missing '=' in line: " + line);
        }
        let key = string.str_trim(string.str_slice(line, 0, eq));
        if key.len() == 0 {
          return _err_pls("pls: empty key in line: " + line);
        }
        let value = string.str_trim(string.str_slice(line, eq + 1, n));
        let lkey = _lower_ascii(key);
        if compare.str_compare(lkey, "version") == 0 {
          let v = _parse_uint(value);
          if v < 0 {
            return _err_pls("pls: bad version: " + value);
          }
          if v != 2 {
            return _err_pls("pls: unsupported version: " + value);
          }
        } elif compare.str_compare(lkey, "numberofentries") == 0 {
          let v = _parse_uint(value);
          if v < 0 {
            return _err_pls("pls: bad NumberOfEntries: " + value);
          }
          if v > _MAX_ENTRIES {
            return _err_pls("pls: too many entries: " + value);
          }
          declared = v;
        } else {
          let kind = _indexed_kind(lkey);
          if kind < 0 {
            unknown_keys.push(key);
            unknown_values.push(value);
          } else {
            let base = _indexed_base(kind);
            let suffix = string.str_slice(key, base, key.len());
            let idx = _parse_uint(suffix);
            if idx < 1 {
              return _err_pls("pls: bad index in key: " + key);
            }
            if idx > _MAX_ENTRIES {
              return _err_pls("pls: index out of range: " + key);
            }
            var num = 0;
            if kind == _KIND_LENGTH {
              num = _parse_length(value);
              if num == -2 {
                return _err_pls("pls: bad length in key " + key + ": " + value);
              }
            }
            rec_kind.push(kind);
            rec_index.push(idx);
            rec_num.push(num);
            rec_key.push(key);
            rec_value.push(value);
          }
        }
      }
    }
    li = li + 1;
  }
  // Cross-line checks run after the scan, so they are independent of where
  // NumberOfEntries appears in the document.
  var m = declared;
  if m < 0 {
    m = 0;
    var r0 = 0;
    while r0 < rec_index.len() {
      let ri: Int = rec_index[r0];
      if ri > m { m = ri; }
      r0 = r0 + 1;
    }
  } else {
    var r1 = 0;
    while r1 < rec_index.len() {
      let ri: Int = rec_index[r1];
      if ri > m {
        let rk: Str = rec_key[r1];
        return _err_pls("pls: index out of range: " + rk);
      }
      r1 = r1 + 1;
    }
  }
  var files = Vec[Str].new();
  var titles = Vec[Str].new();
  var lengths = Vec[Int].new();
  var a = 0;
  while a < m {
    files.push("");
    titles.push("");
    lengths.push(-1);
    a = a + 1;
  }
  var r = 0;
  while r < rec_kind.len() {
    let kind: Int = rec_kind[r];
    let pos: Int = rec_index[r] - 1;
    if kind == _KIND_FILE {
      let rv: Str = rec_value[r];
      files[pos] = rv;
    } elif kind == _KIND_TITLE {
      let rv: Str = rec_value[r];
      titles[pos] = rv;
    } else {
      let rn: Int = rec_num[r];
      lengths[pos] = rn;
    }
    r = r + 1;
  }
  var c = 0;
  while c < m {
    let f: Str = files[c];
    if f.len() == 0 {
      return _err_pls("pls: missing File" + convert.int_to_string(c + 1));
    }
    c = c + 1;
  }
  return _ok_pls(_make_pls(has_header, files, titles, lengths,
                           unknown_keys, unknown_values));
}

/// Emit one playlist in canonical PLS form.
/// Params: p - the playlist to serialize.
/// Returns: "[playlist]" and "Version=2" lines, then "NumberOfEntries="
/// recomputed from the actual entry count, then per entry (1-based N) always
/// "FileN=<file>", "TitleN=<title>" only when the title is non-empty, and
/// "LengthN=<seconds>" only when the length is >= 0. Unknown keys follow the
/// entries in stored order, with their values verbatim. Every line is
/// LF-terminated, so the result always ends with LF; an empty playlist emits
/// "[playlist]\nVersion=2\nNumberOfEntries=0\n". A value carrying an embedded
/// LF byte would corrupt the emitted line layout; parse can never produce one
/// (and Str cannot carry an embedded NUL, so sb_to_str never aborts here).
/// Error case: none.
/// Complexity: O(total output length).
pub fn pls_emit(p: &Pls) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "[playlist]\n");
  builder.sb_push_str(&mut out, "Version=2\n");
  builder.sb_push_str(&mut out, "NumberOfEntries=");
  builder.sb_push_int(&mut out, p.files.len());
  out.push(10u8);
  let n = p.files.len();
  var i = 0;
  while i < n {
    let idx = i + 1;
    builder.sb_push_str(&mut out, "File");
    builder.sb_push_int(&mut out, idx);
    out.push(61u8);
    let f: Str = p.files[i];
    builder.sb_push_str(&mut out, f);
    out.push(10u8);
    if i < p.titles.len() {
      let t: Str = p.titles[i];
      if t.len() > 0 {
        builder.sb_push_str(&mut out, "Title");
        builder.sb_push_int(&mut out, idx);
        out.push(61u8);
        builder.sb_push_str(&mut out, t);
        out.push(10u8);
      }
    }
    if i < p.lengths.len() {
      let l: Int = p.lengths[i];
      if l >= 0 {
        builder.sb_push_str(&mut out, "Length");
        builder.sb_push_int(&mut out, idx);
        out.push(61u8);
        builder.sb_push_int(&mut out, l);
        out.push(10u8);
      }
    }
    i = i + 1;
  }
  var j = 0;
  while j < p.unknown_keys.len() {
    let k: Str = p.unknown_keys[j];
    builder.sb_push_str(&mut out, k);
    out.push(61u8);
    if j < p.unknown_values.len() {
      let v: Str = p.unknown_values[j];
      builder.sb_push_str(&mut out, v);
    }
    out.push(10u8);
    j = j + 1;
  }
  return builder.sb_to_str(&out);
}

/// Number of entries. Entry indexes for the accessors are 1-based, matching
/// FileN..File1..N.
pub fn pls_entry_count(p: &Pls) -> Int {
  return p.files.len();
}

/// True when the document contained a `[playlist]` section header line.
pub fn pls_has_header(p: &Pls) -> Bool {
  return p.has_header;
}

/// File path of entry `i` (1-based, verbatim after trimming); "" when `i` is
/// out of range.
pub fn pls_file(p: &Pls, i: Int) -> Str {
  if i < 1 { return ""; }
  if i > p.files.len() { return ""; }
  let v: Str = p.files[i - 1];
  return v;
}

/// Title of entry `i` (1-based, verbatim after trimming); "" when `i` is out
/// of range or the entry had no TitleN.
pub fn pls_title(p: &Pls, i: Int) -> Str {
  if i < 1 { return ""; }
  if i > p.titles.len() { return ""; }
  let v: Str = p.titles[i - 1];
  return v;
}

/// Whole-second length of entry `i` (1-based); -1 when `i` is out of range
/// or the length is unknown (no LengthN, or explicit LengthN=-1, the
/// documented live-stream sentinel).
pub fn pls_length(p: &Pls, i: Int) -> Int {
  if i < 1 { return -1; }
  if i > p.lengths.len() { return -1; }
  let v: Int = p.lengths[i - 1];
  return v;
}

/// Number of unknown keys preserved from the document.
pub fn pls_unknown_count(p: &Pls) -> Int {
  return p.unknown_keys.len();
}

/// Name of unknown key `j` (0-based, document order); "" when `j` is out of
/// range.
pub fn pls_unknown_key(p: &Pls, j: Int) -> Str {
  if j < 0 { return ""; }
  if j >= p.unknown_keys.len() { return ""; }
  let v: Str = p.unknown_keys[j];
  return v;
}

/// Value of unknown key `j` (0-based, document order); "" when `j` is out of
/// range.
pub fn pls_unknown_value(p: &Pls, j: Int) -> Str {
  if j < 0 { return ""; }
  if j >= p.unknown_values.len() { return ""; }
  let v: Str = p.unknown_values[j];
  return v;
}
