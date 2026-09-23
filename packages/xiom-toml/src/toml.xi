// XIOM -- xiom.toml: TOML v1.0 subset parser with dotted-path lookups
// Port task: replace the xiom.toml placeholder with a real, tested, pure-XIOM
// package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one document is six parallel vectors. `keys` holds the dotted path
// of every entry ("server.port") in document order; `values` holds the scalar
// text of each entry; `kinds` tags each entry (0=str, 1=int, 2=bool,
// 3=str-array, 4=int-array). Array items share one flat `array_items` vector;
// entry i owns array_items[array_starts[i] .. array_starts[i] +
// array_lengths[i]] (0/0 for scalars). Vec[StructType] is unsupported in this
// compiler, so the document is deliberately flat instead of a tree.
//
// Subset: # comments, bare/quoted keys, `key = value`, dotted keys, [table]
// and [a.b] headers, basic strings with \n \t \r \" \\ escapes, literal
// 'strings', integers (optional leading -), booleans and arrays of strings or
// integers. Duplicate keys/tables and malformed lines are Err("toml: ...").
// Multi-line strings, dates, floats, inline tables and arrays of tables are
// unsupported; see SPEC.md.

module xiom.toml

use xiom.string;
use xiom.string.compare;
use xiom.convert;

const _TOML_KIND_STR: Int = 0;
const _TOML_KIND_INT: Int = 1;
const _TOML_KIND_BOOL: Int = 2;
const _TOML_KIND_STR_ARRAY: Int = 3;
const _TOML_KIND_INT_ARRAY: Int = 4;

/// Parsed TOML document. `keys` / `values` / `kinds` / `array_starts` /
/// `array_lengths` are parallel entry vectors; array items live in the shared
/// `array_items` pool. `kinds`: 0=str, 1=int, 2=bool, 3=str-array, 4=int-array.
pub type TomlDoc = {
  keys: Vec[Str];
  values: Vec[Str];
  kinds: Vec[Int];
  array_items: Vec[Str];
  array_starts: Vec[Int];
  array_lengths: Vec[Int];
}

// ---------------------------------------------------------------------------
// Byte predicates
// ---------------------------------------------------------------------------

// True for an ASCII space or horizontal tab (the only intra-line whitespace).
fn _is_ws_byte(b: UInt8) -> Bool {
  return b == 32 || b == 9;
}

// True for a TOML bare-key byte: A-Z a-z 0-9 _ -
fn _is_key_byte(b: UInt8) -> Bool {
  if b >= 97 && b <= 122 { return true; }
  if b >= 65 && b <= 90 { return true; }
  if b >= 48 && b <= 57 { return true; }
  return b == 95 || b == 45;
}

// True when `target` does not occur in v[start, end).
fn _no_byte_in(v: Str, target: UInt8, start: Int, end: Int) -> Bool {
  var i = start;
  while i < end {
    if string.byte_at(v, i) == target { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Basic strings
// ---------------------------------------------------------------------------

// True when v is a complete basic string: "...", allowing only the escapes
// \n \t \r \" \\ and no unescaped inner quote.
fn _basic_string_ok(v: Str) -> Bool {
  let n = v.len();
  if n < 2 { return false; }
  if string.byte_at(v, n - 1) != 34 { return false; }
  var i = 1;
  while i < n - 1 {
    let b = string.byte_at(v, i);
    if b == 92 {
      if i + 1 >= n - 1 { return false; }
      let e = string.byte_at(v, i + 1);
      if e == 110 || e == 116 || e == 114 || e == 34 || e == 92 {
        i = i + 2;
      } else {
        return false;
      }
    } elif b == 34 {
      return false;
    } else {
      i = i + 1;
    }
  }
  return true;
}

// Decode a validated basic string (surrounding quotes removed).
fn _decode_basic(v: Str) -> Str {
  let inner = string.str_slice(v, 1, v.len() - 1);
  var out = Vec[UInt8].new();
  var i = 0;
  while i < inner.len() {
    let b = string.byte_at(inner, i);
    if b == 92 {
      let e = string.byte_at(inner, i + 1);
      if e == 110 { out.push(10u8); }
      elif e == 116 { out.push(9u8); }
      elif e == 114 { out.push(13u8); }
      elif e == 34 { out.push(34u8); }
      else { out.push(92u8); }
      i = i + 2;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return Str::from_utf8(out);
}

// ---------------------------------------------------------------------------
// Scalar values
// ---------------------------------------------------------------------------

// True for an optionally negative run of ASCII digits ("" and "-" are not).
fn _bare_is_int(v: Str) -> Bool {
  let n = v.len();
  if n == 0 { return false; }
  var i = 0;
  if string.byte_at(v, 0) == 45 {
    if n == 1 { return false; }
    i = 1;
  }
  while i < n {
    let b = string.byte_at(v, i);
    if !(b >= 48 && b <= 57) { return false; }
    i = i + 1;
  }
  return true;
}

// True for the bare words true/false.
fn _bare_is_bool(v: Str) -> Bool {
  if compare.str_compare(v, "true") == 0 { return true; }
  return compare.str_compare(v, "false") == 0;
}

// Kind of a trimmed scalar: 0 str, 1 int, 2 bool, -1 malformed.
fn _scalar_kind(v: Str) -> Int {
  let n = v.len();
  if n == 0 { return -1; }
  let b0 = string.byte_at(v, 0);
  if b0 == 34 {
    if _basic_string_ok(v) { return _TOML_KIND_STR; }
    return -1;
  }
  if b0 == 39 {
    if n >= 2 && string.byte_at(v, n - 1) == 39 {
      if _no_byte_in(v, 39, 1, n - 1) { return _TOML_KIND_STR; }
    }
    return -1;
  }
  if _bare_is_int(v) { return _TOML_KIND_INT; }
  if _bare_is_bool(v) { return _TOML_KIND_BOOL; }
  return -1;
}

// Parse a validated integer (optional leading -, otherwise digits).
fn _int_value(v: Str) -> Int {
  var neg = false;
  var i = 0;
  if string.byte_at(v, 0) == 45 {
    neg = true;
    i = 1;
  }
  var acc = 0;
  while i < v.len() {
    acc = acc * 10 + (string.byte_at(v, i) as Int - 48);
    i = i + 1;
  }
  if neg { return 0 - acc; }
  return acc;
}

// Canonical stored text of a classified scalar.
fn _scalar_text(v: Str, kind: Int) -> Str {
  if kind == _TOML_KIND_STR {
    if string.byte_at(v, 0) == 39 {
      return string.str_slice(v, 1, v.len() - 1);
    }
    return _decode_basic(v);
  }
  if kind == _TOML_KIND_INT {
    return convert.int_to_string(_int_value(v));
  }
  return v;
}

// ---------------------------------------------------------------------------
// Arrays
// ---------------------------------------------------------------------------

// Validate a trimmed "[ ... ]" value and push decoded items into `items`.
// Returns 3 (str array), 4 (int array) or -1 for a malformed, mixed-type or
// nested array. An empty array yields 3 with zero items.
fn _array_fill(v: Str, items: &mut Vec[Str]) -> Int {
  let n = v.len();
  if n < 2 { return -1; }
  if string.byte_at(v, 0) != 91 { return -1; }
  if string.byte_at(v, n - 1) != 93 { return -1; }
  let end = n - 1;
  var kind = _TOML_KIND_STR_ARRAY;
  var seen = 0;
  var i = 1;
  while i < end {
    while i < end && _is_ws_byte(string.byte_at(v, i)) { i = i + 1; }
    if i >= end { break; }
    if string.byte_at(v, i) == 44 { return -1; }
    var j = i;
    var in_basic = false;
    var in_lit = false;
    while j < end {
      let b = string.byte_at(v, j);
      if in_basic {
        if b == 92 {
          j = j + 2;
        } elif b == 34 {
          in_basic = false;
          j = j + 1;
        } else {
          j = j + 1;
        }
      } elif in_lit {
        if b == 39 { in_lit = false; }
        j = j + 1;
      } else {
        if b == 34 {
          in_basic = true;
          j = j + 1;
        } elif b == 39 {
          in_lit = true;
          j = j + 1;
        } elif b == 44 {
          break;
        } else {
          j = j + 1;
        }
      }
    }
    let item = string.str_trim(string.str_slice(v, i, j));
    if item.len() == 0 { return -1; }
    let ik = _scalar_kind(item);
    if ik == _TOML_KIND_STR {
      if seen > 0 && kind != _TOML_KIND_STR_ARRAY { return -1; }
      kind = _TOML_KIND_STR_ARRAY;
      items.push(_scalar_text(item, ik));
    } elif ik == _TOML_KIND_INT {
      if seen > 0 && kind != _TOML_KIND_INT_ARRAY { return -1; }
      kind = _TOML_KIND_INT_ARRAY;
      items.push(_scalar_text(item, ik));
    } else {
      return -1;
    }
    seen = seen + 1;
    i = j;
    if i < end { i = i + 1; }
  }
  return kind;
}

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

// Normalize a (possibly dotted, possibly quoted) key into a canonical dotted
// path with trimmed segments. Err("toml: ...") on malformed input.
fn _parse_key_path(s: Str) -> Result[Str, Str] {
  let n = s.len();
  var out = "";
  var segs = 0;
  var i = 0;
  while i < n {
    while i < n && _is_ws_byte(string.byte_at(s, i)) { i = i + 1; }
    if i >= n { break; }
    var seg = "";
    let first = string.byte_at(s, i);
    if first == 34 {
      var j = i + 1;
      var closed = false;
      while j < n {
        let c = string.byte_at(s, j);
        if c == 92 {
          j = j + 2;
        } elif c == 34 {
          closed = true;
          break;
        } else {
          j = j + 1;
        }
      }
      if !closed { return Err("toml: unterminated quoted key: " + s); }
      let sub = string.str_slice(s, i, j + 1);
      if !_basic_string_ok(sub) { return Err("toml: malformed quoted key: " + s); }
      seg = _decode_basic(sub);
      i = j + 1;
    } elif first == 39 {
      var j2 = i + 1;
      var closed2 = false;
      while j2 < n {
        if string.byte_at(s, j2) == 39 {
          closed2 = true;
          break;
        }
        j2 = j2 + 1;
      }
      if !closed2 { return Err("toml: unterminated literal key: " + s); }
      seg = string.str_slice(s, i + 1, j2);
      i = j2 + 1;
    } else {
      var j3 = i;
      while j3 < n && _is_key_byte(string.byte_at(s, j3)) { j3 = j3 + 1; }
      if j3 == i { return Err("toml: malformed key: " + s); }
      seg = string.str_slice(s, i, j3);
      i = j3;
    }
    if seg.len() == 0 { return Err("toml: empty key segment: " + s); }
    if segs > 0 { out = out + "."; }
    out = out + seg;
    segs = segs + 1;
    while i < n && _is_ws_byte(string.byte_at(s, i)) { i = i + 1; }
    if i >= n { break; }
    if string.byte_at(s, i) != 46 { return Err("toml: malformed key: " + s); }
    i = i + 1;
  }
  if segs == 0 { return Err("toml: empty key"); }
  return Ok(out);
}

// ---------------------------------------------------------------------------
// Line scanning
// ---------------------------------------------------------------------------

// Cut `s` at the first # that is outside a basic or literal string.
fn _strip_comment(s: Str) -> Str {
  let n = s.len();
  var in_basic = false;
  var in_lit = false;
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if in_basic {
      if b == 92 {
        i = i + 2;
      } elif b == 34 {
        in_basic = false;
        i = i + 1;
      } else {
        i = i + 1;
      }
    } elif in_lit {
      if b == 39 { in_lit = false; }
      i = i + 1;
    } else {
      if b == 35 {
        return string.str_slice(s, 0, i);
      } elif b == 34 {
        in_basic = true;
        i = i + 1;
      } elif b == 39 {
        in_lit = true;
        i = i + 1;
      } else {
        i = i + 1;
      }
    }
  }
  return s;
}

// Byte index of the first top-level '=' (outside strings), or -1.
fn _find_eq(s: Str) -> Int {
  let n = s.len();
  var in_basic = false;
  var in_lit = false;
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if in_basic {
      if b == 92 {
        i = i + 2;
      } elif b == 34 {
        in_basic = false;
        i = i + 1;
      } else {
        i = i + 1;
      }
    } elif in_lit {
      if b == 39 { in_lit = false; }
      i = i + 1;
    } else {
      if b == 61 {
        return i;
      } elif b == 34 {
        in_basic = true;
        i = i + 1;
      } elif b == 39 {
        in_lit = true;
        i = i + 1;
      } else {
        i = i + 1;
      }
    }
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Document mutation helpers
// ---------------------------------------------------------------------------

// Index of `key` in d.keys, or -1. Str comparisons go through str_compare
// (BUG 17: `==` on Vec[Str] elements lowers to a pointer comparison).
fn _key_index(d: &TomlDoc, key: Str) -> Int {
  var i = 0;
  while i < d.keys.len() {
    if compare.str_compare(d.keys[i], key) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

// True when the list already contains `key`.
fn _list_has(v: &Vec[Str], key: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    if compare.str_compare(v[i], key) == 0 { return true; }
    i = i + 1;
  }
  return false;
}

// Append one scalar entry (0/0 array slice).
fn _doc_push_scalar(doc: &mut TomlDoc, key: Str, value: Str, kind: Int) {
  doc.keys.push(key);
  doc.values.push(value);
  doc.kinds.push(kind);
  doc.array_starts.push(0);
  doc.array_lengths.push(0);
}

// Append one array entry and copy its items into the doc's flat pool.
fn _doc_push_array(doc: &mut TomlDoc, key: Str, items: &Vec[Str], kind: Int) {
  let start = doc.array_items.len();
  doc.keys.push(key);
  doc.values.push("");
  doc.kinds.push(kind);
  doc.array_starts.push(start);
  doc.array_lengths.push(items.len());
  var i = 0;
  while i < items.len() {
    doc.array_items.push(items[i]);
    i = i + 1;
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parse a TOML v1.0 subset document.
/// Params: text - the whole document.
/// Returns: Ok(TomlDoc) for a valid document (including an empty one); Err
/// with a "toml: ..." message on a duplicate key/table, a malformed line or
/// an unsupported construct.
/// Complexity: O(total input length).
pub fn toml_parse(text: Str) -> Result[TomlDoc, Str] {
  var doc = TomlDoc{
    keys: Vec[Str].new();
    values: Vec[Str].new();
    kinds: Vec[Int].new();
    array_items: Vec[Str].new();
    array_starts: Vec[Int].new();
    array_lengths: Vec[Int].new();
  };
  var tables = Vec[Str].new();
  var prefix = "";
  let len = text.len();
  var start = 0;
  var i = 0;
  while i <= len {
    if i == len || string.byte_at(text, i) == 10 {
      var line = string.str_slice(text, start, i);
      let line_len = line.len();
      if line_len > 0 && string.byte_at(line, line_len - 1) == 13 {
        line = string.str_slice(line, 0, line_len - 1);
      }
      line = string.str_trim(_strip_comment(line));
      if line.len() > 0 {
        if string.byte_at(line, 0) == 91 {
          if line.len() >= 2 && string.byte_at(line, 1) == 91 {
            return Err("toml: array of tables is not supported");
          }
          if string.byte_at(line, line.len() - 1) != 93 {
            return Err("toml: malformed table header: " + line);
          }
          let inner = string.str_slice(line, 1, line.len() - 1);
          let hr = _parse_key_path(inner);
          match hr {
            Ok(tname) => {
              if _list_has(&tables, tname) {
                return Err("toml: duplicate table: " + tname);
              }
              tables.push(tname);
              prefix = tname;
            },
            Err(e) => { return Err(e); },
          }
        } else {
          let eq = _find_eq(line);
          if eq < 0 {
            return Err("toml: expected 'key = value': " + line);
          }
          let kr = _parse_key_path(string.str_slice(line, 0, eq));
          match kr {
            Ok(kseg) => {
              var full = kseg;
              if prefix.len() > 0 {
                full = prefix + "." + kseg;
              }
              if _key_index(&doc, full) >= 0 {
                return Err("toml: duplicate key: " + full);
              }
              let val = string.str_trim(string.str_slice(line, eq + 1, line.len()));
              if val.len() == 0 {
                return Err("toml: missing value for key: " + full);
              }
              if string.byte_at(val, 0) == 91 {
                var items = Vec[Str].new();
                let akind = _array_fill(val, &mut items);
                if akind < 0 {
                  return Err("toml: malformed array for key: " + full);
                }
                _doc_push_array(&mut doc, full, &items, akind);
              } else {
                let skind = _scalar_kind(val);
                if skind < 0 {
                  return Err("toml: malformed value for key: " + full);
                }
                _doc_push_scalar(&mut doc, full, _scalar_text(val, skind), skind);
              }
            },
            Err(e) => { return Err(e); },
          }
        }
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return Ok(doc);
}

/// True when the document contains `key`.
pub fn toml_has(d: &TomlDoc, key: Str) -> Bool {
  return _key_index(d, key) >= 0;
}

/// Kind of `key`: 0 str, 1 int, 2 bool, 3 str-array, 4 int-array; None when
/// the key is absent.
pub fn toml_kind(d: &TomlDoc, key: Str) -> Option[Int] {
  let i = _key_index(d, key);
  if i < 0 { return None; }
  return Some(d.kinds[i]);
}

/// String value of `key`; None when absent or of another kind.
pub fn toml_get_str(d: &TomlDoc, key: Str) -> Option[Str] {
  let i = _key_index(d, key);
  if i < 0 { return None; }
  if d.kinds[i] != _TOML_KIND_STR { return None; }
  return Some(d.values[i]);
}

/// Integer value of `key`; None when absent or of another kind.
pub fn toml_get_int(d: &TomlDoc, key: Str) -> Option[Int] {
  let i = _key_index(d, key);
  if i < 0 { return None; }
  if d.kinds[i] != _TOML_KIND_INT { return None; }
  return Some(_int_value(d.values[i]));
}

/// Boolean value of `key`; None when absent or of another kind.
pub fn toml_get_bool(d: &TomlDoc, key: Str) -> Option[Bool] {
  let i = _key_index(d, key);
  if i < 0 { return None; }
  if d.kinds[i] != _TOML_KIND_BOOL { return None; }
  if compare.str_compare(d.values[i], "true") == 0 { return Some(true); }
  return Some(false);
}

/// Items of a string-array `key`; empty for an absent key or another kind.
pub fn toml_get_str_array(d: &TomlDoc, key: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let i = _key_index(d, key);
  if i < 0 { return out; }
  if d.kinds[i] != _TOML_KIND_STR_ARRAY { return out; }
  let start = d.array_starts[i];
  let count = d.array_lengths[i];
  var j = 0;
  while j < count {
    out.push(d.array_items[start + j]);
    j = j + 1;
  }
  return out;
}

/// Parsed items of an int-array `key`; empty for an absent key or another kind.
pub fn toml_get_int_array(d: &TomlDoc, key: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let i = _key_index(d, key);
  if i < 0 { return out; }
  if d.kinds[i] != _TOML_KIND_INT_ARRAY { return out; }
  let start = d.array_starts[i];
  let count = d.array_lengths[i];
  var j = 0;
  while j < count {
    out.push(_int_value(d.array_items[start + j]));
    j = j + 1;
  }
  return out;
}

/// Dotted keys of every entry, in document order (a fresh copy).
pub fn toml_keys(d: &TomlDoc) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < d.keys.len() {
    out.push(d.keys[i]);
    i = i + 1;
  }
  return out;
}

/// Number of entries in the document.
pub fn toml_key_count(d: &TomlDoc) -> Int {
  return d.keys.len();
}
