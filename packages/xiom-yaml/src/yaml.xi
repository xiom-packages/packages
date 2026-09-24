// XIOM -- xiom.yaml: YAML subset parser with dotted-path lookups
// Port task: replace the xiom.yaml placeholder with a real, tested, pure-XIOM
// package (no FFI, no file I/O).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one document is six parallel vectors (see YamlDoc below). `keys`
// holds the dotted path of every leaf entry ("server.port") in document order;
// `values` holds the canonical scalar text; `kinds` tags each entry (0=str,
// 1=int, 2=bool, 3=null, 4=str-list). List items share one flat `list_items`
// pool; entry i owns list_items[list_starts[i] .. list_starts[i] +
// list_lengths[i]] (0/0 for scalars). Mapping containers are implicit in the
// dotted paths, so they have no entry of their own. Vec[StructType] is
// unsupported in this compiler, so the document is deliberately flat instead
// of a tree.
//
// Subset: # comments, blank lines, nested mappings by spaces-only indentation
// with a consistent step, block lists under a key ("- item"), inline scalar
// lists ("[a, b]"), and scalars: plain, 'single' (literal), "double" with
// \n \t \" \\ escapes, integers (optional leading -), true/false, null/~. No
// anchors/aliases, no multi-document streams, no tags, no flow mappings, no
// nested structures inside list items; see SPEC.md for the exact grammar and
// error catalog.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str and
//     byte reads go through _byte(), which widens with `as Int` + `& 0xFF`.
//   * Vec[StructType] is unsupported, so YamlDoc is parallel Vec[Str]/Vec[Int].
//   * `Ok`/`Err` for Result[YamlDoc, Str] are constructed only in the tiny
//     leaf helpers _ok_doc/_err_doc.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).
//   * Match patterns bind no `mut`; the parser dispatches with plain if/elif.

module xiom.yaml

use xiom.string;
use xiom.string.compare;
use xiom.convert;

const _YAML_KIND_STR: Int = 0;
const _YAML_KIND_INT: Int = 1;
const _YAML_KIND_BOOL: Int = 2;
const _YAML_KIND_NULL: Int = 3;
const _YAML_KIND_LIST: Int = 4;

/// Parsed YAML subset document. `keys` / `values` / `kinds` / `list_starts` /
/// `list_lengths` are parallel entry vectors; list items live in the shared
/// `list_items` pool. `kinds`: 0=str, 1=int, 2=bool, 3=null, 4=str-list.
pub type YamlDoc = {
  keys: Vec[Str];
  values: Vec[Str];
  kinds: Vec[Int];
  list_items: Vec[Str];
  list_starts: Vec[Int];
  list_lengths: Vec[Int];
}

// ---------------------------------------------------------------------------
//  Result constructors (see the module header)
// ---------------------------------------------------------------------------

// Ok(d) for Result[YamlDoc, Str].
fn _ok_doc(d: YamlDoc) -> Result[YamlDoc, Str] {
  return Ok(d);
}

// Err(m) for Result[YamlDoc, Str].
fn _err_doc(m: Str) -> Result[YamlDoc, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
//  Byte helpers
// ---------------------------------------------------------------------------

// Byte `i` of `s` widened to Int. UInt8 comparisons widen first (v0.61.3).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for an ASCII space or horizontal tab (the only intra-line whitespace).
fn _is_ws(b: Int) -> Bool {
  return b == 32 || b == 9;
}

// True when a quote at byte `i` of `s` opens a quoted scalar: it sits at the
// line start or right after whitespace, ':', ',', '[' or '-'. A stray quote
// inside a plain scalar does not open a quoted region, so a later "#" can
// still start a comment.
fn _quote_start(s: Str, i: Int) -> Bool {
  if i == 0 {
    return true;
  }
  let p = _byte(s, i - 1);
  if p == 32 || p == 9 || p == 58 || p == 44 || p == 91 || p == 45 {
    return true;
  }
  return false;
}

// Cut `s` at the first "#" that starts a comment: it must be at the line
// start or preceded by whitespace, and outside a quoted region.
fn _strip_comment(s: Str) -> Str {
  let n = s.len();
  var in_dq = false;
  var in_sq = false;
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if in_dq {
      if b == 92 {
        i = i + 2;
      } elif b == 34 {
        in_dq = false;
        i = i + 1;
      } else {
        i = i + 1;
      }
    } elif in_sq {
      if b == 39 {
        in_sq = false;
      }
      i = i + 1;
    } else {
      if b == 35 && (i == 0 || _is_ws(_byte(s, i - 1))) {
        return string.str_slice(s, 0, i);
      } elif b == 34 && _quote_start(s, i) {
        in_dq = true;
        i = i + 1;
      } elif b == 39 && _quote_start(s, i) {
        in_sq = true;
        i = i + 1;
      } else {
        i = i + 1;
      }
    }
  }
  return s;
}

// ---------------------------------------------------------------------------
//  Scalar classification
// ---------------------------------------------------------------------------

// Quoting status of a trimmed scalar:
//   0  not quoted (plain)
//   2  complete double-quoted string ("..." with \n \t \" \\ only)
//   1  complete single-quoted string ('...' with no inner quote)
//  -1  unterminated quote
//  -2  invalid escape in a double-quoted string
//  -3  trailing text after the closing quote
fn _q_status(v: Str) -> Int {
  let n = v.len();
  if n == 0 {
    return 0;
  }
  let b0 = _byte(v, 0);
  if b0 == 34 {
    var i = 1;
    while i < n {
      let b = _byte(v, i);
      if b == 92 {
        if i + 1 >= n {
          return -1;
        }
        let e = _byte(v, i + 1);
        if e == 110 || e == 116 || e == 34 || e == 92 {
          i = i + 2;
        } else {
          return -2;
        }
      } elif b == 34 {
        if i == n - 1 {
          return 2;
        }
        return -3;
      } else {
        i = i + 1;
      }
    }
    return -1;
  }
  if b0 == 39 {
    var j = 1;
    while j < n {
      if _byte(v, j) == 39 {
        if j == n - 1 {
          return 1;
        }
        return -3;
      }
      j = j + 1;
    }
    return -1;
  }
  return 0;
}

// Decode a validated double-quoted scalar (quotes removed).
fn _dq_decode(v: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 1;
  let stop = v.len() - 1;
  while i < stop {
    let b = _byte(v, i);
    if b == 92 {
      let e = _byte(v, i + 1);
      if e == 110 {
        out.push(10u8);
      } elif e == 116 {
        out.push(9u8);
      } elif e == 34 {
        out.push(34u8);
      } else {
        out.push(92u8);
      }
      i = i + 2;
    } else {
      out.push(string.byte_at(v, i));
      i = i + 1;
    }
  }
  return Str::from_utf8(out);
}

// Text of a validated single-quoted scalar (quotes removed, no escapes).
fn _sq_text(v: Str) -> Str {
  return string.str_slice(v, 1, v.len() - 1);
}

// True for an optionally negative run of ASCII digits ("" and "-" are not).
fn _is_int_text(v: Str) -> Bool {
  let n = v.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  if _byte(v, 0) == 45 {
    if n == 1 {
      return false;
    }
    i = 1;
  }
  while i < n {
    let b = _byte(v, i);
    if !(b >= 48 && b <= 57) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Parse a validated integer (optional leading -, otherwise digits).
fn _int_value(v: Str) -> Int {
  var neg = false;
  var i = 0;
  if _byte(v, 0) == 45 {
    neg = true;
    i = 1;
  }
  var acc = 0;
  while i < v.len() {
    acc = acc * 10 + (_byte(v, i) - 48);
    i = i + 1;
  }
  if neg {
    return 0 - acc;
  }
  return acc;
}

// True for the bare words true/false.
fn _is_bool_text(v: Str) -> Bool {
  if compare.str_compare(v, "true") == 0 {
    return true;
  }
  return compare.str_compare(v, "false") == 0;
}

// True for the null words null/~.
fn _is_null_text(v: Str) -> Bool {
  if compare.str_compare(v, "null") == 0 {
    return true;
  }
  return compare.str_compare(v, "~") == 0;
}

// True when a plain scalar carries unsupported mapping syntax: a ":" at the
// end or followed by whitespace ("a: b").
fn _has_map_syntax(v: Str) -> Bool {
  let n = v.len();
  var i = 0;
  while i < n {
    if _byte(v, i) == 58 {
      if i == n - 1 {
        return true;
      }
      if _is_ws(_byte(v, i + 1)) {
        return true;
      }
    }
    i = i + 1;
  }
  return false;
}

// True when a would-be plain list item opens a nested sequence ("- " or "-").
fn _starts_list_indicator(v: Str) -> Bool {
  if v.len() == 0 {
    return false;
  }
  if _byte(v, 0) != 45 {
    return false;
  }
  return v.len() == 1 || _byte(v, 1) == 32;
}

// ---------------------------------------------------------------------------
//  Inline lists
// ---------------------------------------------------------------------------

// Validate a trimmed "[ ... ]" value and push decoded items into `items`.
// Returns 4 on success, or -1 malformed list, -2 unterminated quote,
// -3 invalid escape, -4 text after a quoted item closes. An empty list
// yields 4 with zero items; a trailing comma is accepted.
fn _list_fill(v: Str, items: &mut Vec[Str]) -> Int {
  let n = v.len();
  if n < 2 {
    return -1;
  }
  if _byte(v, 0) != 91 {
    return -1;
  }
  var close = -1;
  var in_dq = false;
  var in_sq = false;
  var i = 1;
  while i < n {
    let b = _byte(v, i);
    if in_dq {
      if b == 92 {
        i = i + 2;
      } elif b == 34 {
        in_dq = false;
        i = i + 1;
      } else {
        i = i + 1;
      }
    } elif in_sq {
      if b == 39 {
        in_sq = false;
      }
      i = i + 1;
    } else {
      if b == 34 && _quote_start(v, i) {
        in_dq = true;
        i = i + 1;
      } elif b == 39 && _quote_start(v, i) {
        in_sq = true;
        i = i + 1;
      } elif b == 93 {
        close = i;
        break;
      } else {
        i = i + 1;
      }
    }
  }
  if close < 0 {
    if in_dq || in_sq {
      return -2;
    }
    return -1;
  }
  if close != n - 1 {
    return -1;
  }
  let end = close;
  var p = 1;
  while p < end {
    while p < end && _is_ws(_byte(v, p)) {
      p = p + 1;
    }
    if p >= end {
      break;
    }
    var j = p;
    var q_dq = false;
    var q_sq = false;
    while j < end {
      let b = _byte(v, j);
      if q_dq {
        if b == 92 {
          j = j + 2;
        } elif b == 34 {
          q_dq = false;
          j = j + 1;
        } else {
          j = j + 1;
        }
      } elif q_sq {
        if b == 39 {
          q_sq = false;
        }
        j = j + 1;
      } else {
        if b == 34 && _quote_start(v, j) {
          q_dq = true;
          j = j + 1;
        } elif b == 39 && _quote_start(v, j) {
          q_sq = true;
          j = j + 1;
        } elif b == 44 {
          break;
        } else {
          j = j + 1;
        }
      }
    }
    let item = string.str_trim(string.str_slice(v, p, j));
    if item.len() == 0 {
      return -1;
    }
    let st = _q_status(item);
    if st == 2 {
      items.push(_dq_decode(item));
    } elif st == 1 {
      items.push(_sq_text(item));
    } elif st == -1 {
      return -2;
    } elif st == -2 {
      return -3;
    } elif st == -3 {
      return -4;
    } else {
      let b0 = _byte(item, 0);
      if b0 == 91 || b0 == 123 || _starts_list_indicator(item) || _has_map_syntax(item) {
        return -1;
      }
      items.push(item);
    }
    p = j;
    if p < end {
      if _byte(v, p) != 44 {
        return -1;
      }
      p = p + 1;
    }
  }
  return 4;
}

// ---------------------------------------------------------------------------
//  Document helpers
// ---------------------------------------------------------------------------

// Index of `key` in d.keys, or -1. Str comparisons go through str_compare
// (BUG 17: `==` on Vec[Str] elements lowers to a pointer comparison).
fn _key_index(d: &YamlDoc, key: Str) -> Int {
  var i = 0;
  while i < d.keys.len() {
    let k: Str = d.keys[i];
    if compare.str_compare(k, key) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when the list already contains `key`.
fn _list_has(v: &Vec[Str], key: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    let k: Str = v[i];
    if compare.str_compare(k, key) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Append one scalar entry (0/0 list slice). `value` is already canonical:
// decoded string, canonical integer text, "true"/"false", or "" for null.
fn _doc_push_scalar(doc: &mut YamlDoc, key: Str, value: Str, kind: Int) {
  doc.keys.push(key);
  doc.values.push(value);
  doc.kinds.push(kind);
  doc.list_starts.push(0);
  doc.list_lengths.push(0);
}

// Append an empty list entry (kind 4) and return its index, so the caller can
// append items to the shared pool as they arrive.
fn _doc_push_list(doc: &mut YamlDoc, key: Str) -> Int {
  let idx = doc.keys.len();
  let start = doc.list_items.len();
  doc.keys.push(key);
  doc.values.push("");
  doc.kinds.push(_YAML_KIND_LIST);
  doc.list_starts.push(start);
  doc.list_lengths.push(0);
  return idx;
}

// Append one item to the list entry `idx`.
fn _doc_list_append(doc: &mut YamlDoc, idx: Int, item: Str) {
  doc.list_items.push(item);
  doc.list_lengths[idx] = doc.list_lengths[idx] + 1;
}

// First byte index of ':' in `s`, or -1. Keys are plain text, so the first
// colon always separates the key from the value.
fn _find_colon(s: Str) -> Int {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == 58 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
//  Public API
// ---------------------------------------------------------------------------

/// Parse a YAML subset document.
/// Params: text - the whole document (LF or CRLF line endings).
/// Returns: Ok(YamlDoc) for a valid document (including an empty one); Err
/// with a "yaml: ..." message on a tab indent, an indentation jump, a
/// duplicate key, a malformed list item, an unterminated quote or another
/// malformed line.
/// Complexity: O(total input length * key count) because duplicate detection
/// scans the seen-path list per key line; O(total input length) with a hash.
pub fn yaml_parse(text: Str) -> Result[YamlDoc, Str] {
  var doc = YamlDoc{
    keys: Vec[Str].new();
    values: Vec[Str].new();
    kinds: Vec[Int].new();
    list_items: Vec[Str].new();
    list_starts: Vec[Int].new();
    list_lengths: Vec[Int].new();
  };
  var seen = Vec[Str].new();
  var indents = Vec[Int].new();
  indents.push(0);
  var prefixes = Vec[Str].new();
  prefixes.push("");
  var list_ids = Vec[Int].new();
  list_ids.push(-1);
  var depth = 1;
  var step = -1;
  var pending = false;
  var pending_full = "";
  let len = text.len();
  var line_start = 0;
  var i = 0;
  while i <= len {
    if i == len || _byte(text, i) == 10 {
      var line = string.str_slice(text, line_start, i);
      let raw_len = line.len();
      if raw_len > 0 && _byte(line, raw_len - 1) == 13 {
        line = string.str_slice(line, 0, raw_len - 1);
      }
      let content = string.str_trim(_strip_comment(line));
      if content.len() > 0 {
        let lt = string.str_trim(line);
        // Leading indentation: spaces only; a tab before the content is an
        // error. Blank and comment-only lines were already skipped.
        var ind = 0;
        while ind < line.len() {
          let b = _byte(line, ind);
          if b == 32 {
            ind = ind + 1;
          } elif b == 9 {
            return _err_doc("yaml: tab indentation is not allowed: " + lt);
          } else {
            break;
          }
        }
        let is_item = _byte(content, 0) == 45 && (content.len() == 1 || _byte(content, 1) == 32);
        var pushed = false;
        if pending {
          let top_ind: Int = indents[depth - 1];
          if ind > top_ind {
            if step < 0 {
              step = ind - top_ind;
            } elif ind - top_ind != step {
              return _err_doc("yaml: indentation jump: " + lt);
            }
            var new_list_id = -1;
            if is_item {
              new_list_id = _doc_push_list(&mut doc, pending_full);
            }
            if depth < indents.len() {
              indents[depth] = ind;
              prefixes[depth] = pending_full;
              list_ids[depth] = new_list_id;
            } else {
              indents.push(ind);
              prefixes.push(pending_full);
              list_ids.push(new_list_id);
            }
            depth = depth + 1;
            pending = false;
            pushed = true;
          } else {
            // The pending "key:" had no indented block: it is null.
            _doc_push_scalar(&mut doc, pending_full, "", _YAML_KIND_NULL);
            pending = false;
          }
        }
        if !pushed && ind > indents[depth - 1] {
          return _err_doc("yaml: indentation jump: " + lt);
        }
        while depth > 1 && ind < indents[depth - 1] {
          depth = depth - 1;
        }
        if ind != indents[depth - 1] {
          return _err_doc("yaml: indentation jump: " + lt);
        }
        let top_list: Int = list_ids[depth - 1];
        if is_item {
          if top_list < 0 {
            return _err_doc("yaml: malformed list item: " + lt);
          }
          let item_raw = string.str_trim(string.str_slice(content, 1, content.len()));
          if item_raw.len() == 0 {
            return _err_doc("yaml: malformed list item: " + lt);
          }
          let st = _q_status(item_raw);
          if st == 2 {
            _doc_list_append(&mut doc, top_list, _dq_decode(item_raw));
          } elif st == 1 {
            _doc_list_append(&mut doc, top_list, _sq_text(item_raw));
          } elif st == -1 {
            return _err_doc("yaml: unterminated quote: " + lt);
          } elif st == -2 {
            return _err_doc("yaml: invalid escape: " + lt);
          } elif st == -3 {
            return _err_doc("yaml: unexpected text after quoted value: " + lt);
          } else {
            let b0 = _byte(item_raw, 0);
            if b0 == 91 || b0 == 123 || _starts_list_indicator(item_raw) || _has_map_syntax(item_raw) {
              return _err_doc("yaml: malformed list item: " + lt);
            }
            _doc_list_append(&mut doc, top_list, item_raw);
          }
        } else {
          if top_list >= 0 {
            // A mapping line at a level already used as a block list.
            return _err_doc("yaml: malformed list item: " + lt);
          }
          let colon = _find_colon(content);
          if colon < 0 {
            return _err_doc("yaml: expected 'key: value': " + lt);
          }
          let key = string.str_trim(string.str_slice(content, 0, colon));
          if key.len() == 0 {
            return _err_doc("yaml: empty key: " + lt);
          }
          if _byte(key, 0) == 34 || _byte(key, 0) == 39 {
            return _err_doc("yaml: quoted keys are not supported: " + lt);
          }
          var full = key;
          let pfx: Str = prefixes[depth - 1];
          if pfx.len() > 0 {
            full = pfx + "." + key;
          }
          if _list_has(&seen, full) {
            return _err_doc("yaml: duplicate key: " + full);
          }
          seen.push(full);
          let value = string.str_trim(string.str_slice(content, colon + 1, content.len()));
          if value.len() == 0 {
            pending = true;
            pending_full = full;
          } else {
            let st = _q_status(value);
            if st == 2 {
              _doc_push_scalar(&mut doc, full, _dq_decode(value), _YAML_KIND_STR);
            } elif st == 1 {
              _doc_push_scalar(&mut doc, full, _sq_text(value), _YAML_KIND_STR);
            } elif st == -1 {
              return _err_doc("yaml: unterminated quote: " + lt);
            } elif st == -2 {
              return _err_doc("yaml: invalid escape: " + lt);
            } elif st == -3 {
              return _err_doc("yaml: unexpected text after quoted value: " + lt);
            } elif _byte(value, 0) == 91 {
              var items = Vec[Str].new();
              let lst = _list_fill(value, &mut items);
              if lst == 4 {
                let li = _doc_push_list(&mut doc, full);
                var q = 0;
                while q < items.len() {
                  let it: Str = items[q];
                  _doc_list_append(&mut doc, li, it);
                  q = q + 1;
                }
              } elif lst == -2 {
                return _err_doc("yaml: unterminated quote: " + lt);
              } elif lst == -3 {
                return _err_doc("yaml: invalid escape: " + lt);
              } elif lst == -4 {
                return _err_doc("yaml: unexpected text after quoted value: " + lt);
              } else {
                return _err_doc("yaml: malformed inline list: " + lt);
              }
            } elif _is_bool_text(value) {
              _doc_push_scalar(&mut doc, full, value, _YAML_KIND_BOOL);
            } elif _is_null_text(value) {
              _doc_push_scalar(&mut doc, full, "", _YAML_KIND_NULL);
            } elif _is_int_text(value) {
              _doc_push_scalar(&mut doc, full, convert.int_to_string(_int_value(value)), _YAML_KIND_INT);
            } elif _byte(value, 0) == 123 || _starts_list_indicator(value) || _has_map_syntax(value) {
              return _err_doc("yaml: malformed value for key: " + full);
            } else {
              _doc_push_scalar(&mut doc, full, value, _YAML_KIND_STR);
            }
          }
        }
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  if pending {
    _doc_push_scalar(&mut doc, pending_full, "", _YAML_KIND_NULL);
  }
  return _ok_doc(doc);
}

/// True when the document contains the dotted `key`.
pub fn yaml_has(d: &YamlDoc, key: Str) -> Bool {
  return _key_index(d, key) >= 0;
}

/// Kind of `key`: 0 str, 1 int, 2 bool, 3 null, 4 str-list; None when the key
/// is absent. Mapping containers have no entry of their own.
pub fn yaml_kind(d: &YamlDoc, key: Str) -> Option[Int] {
  let i = _key_index(d, key);
  if i < 0 {
    return None;
  }
  return Some(d.kinds[i]);
}

/// String value of `key`; None when absent or of another kind.
pub fn yaml_get_str(d: &YamlDoc, key: Str) -> Option[Str] {
  let i = _key_index(d, key);
  if i < 0 {
    return None;
  }
  let k: Int = d.kinds[i];
  if k != _YAML_KIND_STR {
    return None;
  }
  let v: Str = d.values[i];
  return Some(v);
}

/// Integer value of `key`; None when absent or of another kind.
pub fn yaml_get_int(d: &YamlDoc, key: Str) -> Option[Int] {
  let i = _key_index(d, key);
  if i < 0 {
    return None;
  }
  let k: Int = d.kinds[i];
  if k != _YAML_KIND_INT {
    return None;
  }
  let v: Str = d.values[i];
  return Some(_int_value(v));
}

/// Boolean value of `key`; None when absent or of another kind.
pub fn yaml_get_bool(d: &YamlDoc, key: Str) -> Option[Bool] {
  let i = _key_index(d, key);
  if i < 0 {
    return None;
  }
  let k: Int = d.kinds[i];
  if k != _YAML_KIND_BOOL {
    return None;
  }
  let v: Str = d.values[i];
  if compare.str_compare(v, "true") == 0 {
    return Some(true);
  }
  return Some(false);
}

/// Items of a str-list `key`; empty for an absent key or another kind.
pub fn yaml_get_str_list(d: &YamlDoc, key: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let i = _key_index(d, key);
  if i < 0 {
    return out;
  }
  let k: Int = d.kinds[i];
  if k != _YAML_KIND_LIST {
    return out;
  }
  let start: Int = d.list_starts[i];
  let count: Int = d.list_lengths[i];
  var j = 0;
  while j < count {
    let it: Str = d.list_items[start + j];
    out.push(it);
    j = j + 1;
  }
  return out;
}

/// Dotted keys of every leaf entry, in document order (a fresh copy).
pub fn yaml_keys(d: &YamlDoc) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < d.keys.len() {
    let k: Str = d.keys[i];
    out.push(k);
    i = i + 1;
  }
  return out;
}

/// Number of leaf entries in the document.
pub fn yaml_key_count(d: &YamlDoc) -> Int {
  return d.keys.len();
}
