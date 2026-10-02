// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.k8s.selector: label sets and selector matching
// Port task: replace the xiom.k8s placeholder with a real, tested, pure-XIOM
// package (no API server, no networking, no FFI).
//
// A label is an ordered "key=value" entry. Labels are stored as one Str blob
// plus a monotone Vec[Int] offset table (never Vec[Str]); cluster-wide label
// stores additionally carry a parallel Vec[Int] owner table so a pod's labels
// are the entries whose owner equals the pod id. Values are byte-exact and
// case-sensitive: every comparison goes through string.str_compare.
//
// A selector is a set of "key=value" entries; a label set matches a selector
// when it contains every selector entry. Empty selectors match everything
// (callers decide whether that is meaningful).
//
// Language notes (XIOM v0.62.2): free functions only; Ok/Err are constructed
// only inside the _s_* leaf helpers; every Vec[Int] element read binds a
// typed local; parallel arrays are guarded against length drift; ASCII byte
// classifiers mask widened bytes with `& 0xFF`.

module xiom.k8s.selector

use xiom.string;

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

/// An ordered "key=value" entry set. `data` is the concatenated blob and
/// `off` a monotone offset table with off.len() == count + 1 and
/// off[count] == string.str_len(data). Fields are implementation detail.
pub type LabelParts = {
  data: Str;
  off: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only)
// ---------------------------------------------------------------------------

fn _s_ok_parts(v: LabelParts) -> Result[LabelParts, Str] { return Ok(v); }
fn _s_err_parts(m: Str) -> Result[LabelParts, Str] { return Err(m); }
fn _s_ok_int(v: Int) -> Result[Int, Str] { return Ok(v); }
fn _s_err_int(m: Str) -> Result[Int, Str] { return Err(m); }
fn _s_ok_str(v: Str) -> Result[Str, Str] { return Ok(v); }
fn _s_err_str(m: Str) -> Result[Str, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Character classifiers (ASCII only)
// ---------------------------------------------------------------------------

fn _s_is_lower(c: Int) -> Bool { return c >= 0x61 && c <= 0x7A; }
fn _s_is_upper(c: Int) -> Bool { return c >= 0x41 && c <= 0x5A; }
fn _s_is_digit(c: Int) -> Bool { return c >= 0x30 && c <= 0x39; }

fn _s_is_alnum(c: Int) -> Bool {
  if _s_is_lower(c) { return true; }
  if _s_is_upper(c) { return true; }
  return _s_is_digit(c);
}

fn _s_is_key_char(c: Int) -> Bool {
  if _s_is_alnum(c) { return true; }
  if c == 0x2D { return true; }
  if c == 0x5F { return true; }
  if c == 0x2E { return true; }
  if c == 0x2F { return true; }
  return false;
}

/// True when `k` is a valid label key: 1..63 bytes of [A-Za-z0-9._/-], first
/// and last byte alphanumeric. Complexity: O(len).
pub fn label_key_valid(k: Str) -> Bool {
  let n = string.str_len(k);
  if n < 1 || n > 63 { return false; }
  let first: Int = (string.byte_at(k, 0) as Int) & 0xFF;
  let last: Int = (string.byte_at(k, n - 1) as Int) & 0xFF;
  if !_s_is_alnum(first) { return false; }
  if !_s_is_alnum(last) { return false; }
  var i = 1;
  while i < n - 1 {
    let b: Int = (string.byte_at(k, i) as Int) & 0xFF;
    if !_s_is_key_char(b) { return false; }
    i = i + 1;
  }
  return true;
}

/// True when `v` is a valid label value: 0..63 bytes of [A-Za-z0-9._/-];
/// non-empty values must start and end alphanumeric. Complexity: O(len).
pub fn label_value_valid(v: Str) -> Bool {
  let n = string.str_len(v);
  if n > 63 { return false; }
  if n == 0 { return true; }
  let first: Int = (string.byte_at(v, 0) as Int) & 0xFF;
  let last: Int = (string.byte_at(v, n - 1) as Int) & 0xFF;
  if !_s_is_alnum(first) { return false; }
  if !_s_is_alnum(last) { return false; }
  var i = 1;
  while i < n - 1 {
    let b: Int = (string.byte_at(v, i) as Int) & 0xFF;
    if !_s_is_key_char(b) { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Blob helpers
// ---------------------------------------------------------------------------

// Append `s` to blob `data`/`off`. Precondition: off is non-empty with its
// last entry equal to string.str_len(data); the caller assigns the result.
fn _s_blob_append(data: Str, off: &mut Vec[Int], s: Str) -> Str {
  let start: Int = off[off.len() - 1];
  off.push(start + string.str_len(s));
  return data + s;
}

// Entry i of blob `data`/`off`, or "" when out of range.
fn _s_entry(data: Str, off: &Vec[Int], i: Int) -> Str {
  if i < 0 || i >= off.len() - 1 { return ""; }
  let a: Int = off[i];
  let b: Int = off[i + 1];
  return string.str_slice(data, a, b);
}

// First '=' of entry `e`, or -1.
fn _s_find_eq(e: Str) -> Int {
  let n = string.str_len(e);
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(e, i) as Int) & 0xFF;
    if b == 0x3D { return i; }
    i = i + 1;
  }
  return -1;
}

/// Key part of a raw "key=value" entry ("" when there is no '=').
pub fn label_entry_key(e: Str) -> Str {
  let at = _s_find_eq(e);
  if at < 0 { return ""; }
  return string.str_slice(e, 0, at);
}

/// Value part of a raw "key=value" entry ("" when there is no '=').
pub fn label_entry_value(e: Str) -> Str {
  let at = _s_find_eq(e);
  if at < 0 { return ""; }
  return string.str_slice(e, at + 1, string.str_len(e));
}

// Index of `key` in the plain blob, or -1.
fn _s_find(data: Str, off: &Vec[Int], key: Str) -> Int {
  let cnt = off.len() - 1;
  var i = 0;
  while i < cnt {
    let a: Int = off[i];
    let b: Int = off[i + 1];
    let e: Str = string.str_slice(data, a, b);
    if string.str_compare(label_entry_key(e), key) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Single-owner label sets (LabelParts)
// ---------------------------------------------------------------------------

/// Empty label set. Complexity: O(1).
pub fn label_parts_new() -> LabelParts {
  var off = Vec[Int].new();
  off.push(0);
  return LabelParts{ data: ""; off: off; };
}

/// Number of entries. Complexity: O(1).
pub fn label_parts_count(l: &LabelParts) -> Int {
  return l.off.len() - 1;
}

/// Raw "key=value" entry `i`, or "" when out of range.
pub fn label_parts_entry(l: &LabelParts, i: Int) -> Str {
  return _s_entry(l.data, &l.off, i);
}

/// Value of `key`, or "" when absent. Complexity: O(n).
pub fn label_parts_value(l: &LabelParts, key: Str) -> Str {
  let k = _s_find(l.data, &l.off, key);
  if k < 0 { return ""; }
  return label_entry_value(label_parts_entry(l, k));
}

/// True when `key` is present. Complexity: O(n).
pub fn label_parts_has(l: &LabelParts, key: Str) -> Bool {
  return _s_find(l.data, &l.off, key) >= 0;
}

/// Append one validated entry; duplicate keys are rejected and the set is
/// unchanged on every error. Returns the new entry count.
/// Errors: "label: key must not be empty", "label: invalid key",
/// "label: invalid value", "label: duplicate key".
pub fn label_parts_add(l: &mut LabelParts, key: Str, val: Str) -> Result[Int, Str] {
  if string.str_len(key) == 0 { return _s_err_int("label: key must not be empty"); }
  if !label_key_valid(key) { return _s_err_int("label: invalid key"); }
  if !label_value_valid(val) { return _s_err_int("label: invalid value"); }
  if _s_find(l.data, &l.off, key) >= 0 { return _s_err_int("label: duplicate key"); }
  l.data = _s_blob_append(l.data, &mut l.off, key + "=" + val);
  return _s_ok_int(l.off.len() - 1);
}

/// Render the set as "k=v,k2=v2" in insertion order ("" when empty).
pub fn label_parts_render(l: &LabelParts) -> Str {
  var out = "";
  let cnt = l.off.len() - 1;
  var i = 0;
  while i < cnt {
    if i > 0 { out = out + ","; }
    out = out + _s_entry(l.data, &l.off, i);
    i = i + 1;
  }
  return out;
}

// Parse one "key=value" chunk into `l`.
fn _s_parse_chunk(l: &mut LabelParts, chunk: Str) -> Result[Int, Str] {
  if string.str_len(chunk) == 0 { return _s_err_int("label: empty selector entry"); }
  let at = _s_find_eq(chunk);
  if at < 0 { return _s_err_int("label: missing '='"); }
  let key = string.str_slice(chunk, 0, at);
  let val = string.str_slice(chunk, at + 1, string.str_len(chunk));
  return label_parts_add(l, key, val);
}

/// Parse "k=v,k2=v2" (empty string = empty set; no whitespace handling).
/// Errors: "label: empty selector entry", "label: missing '='" plus the
/// label_parts_add errors. Complexity: O(len).
pub fn label_parts_parse(s: Str) -> Result[LabelParts, Str] {
  var l = label_parts_new();
  let n = string.str_len(s);
  if n == 0 { return _s_ok_parts(l); }
  var start = 0;
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 0x2C {
      match _s_parse_chunk(&mut l, string.str_slice(s, start, i)) {
        Ok(_) => {},
        Err(emsg) => { return _s_err_parts(emsg); },
      }
      start = i + 1;
    }
    i = i + 1;
  }
  match _s_parse_chunk(&mut l, string.str_slice(s, start, n)) {
    Ok(_) => {},
    Err(emsg) => { return _s_err_parts(emsg); },
  }
  return _s_ok_parts(l);
}

/// True when every entry of `sel` is present in `labels` with the same value
/// (an empty selector matches everything). Complexity: O(n*m).
pub fn label_parts_matches(labels: &LabelParts, sel: &LabelParts) -> Bool {
  let cnt = sel.off.len() - 1;
  var i = 0;
  while i < cnt {
    let e = label_parts_entry(sel, i);
    let key = label_entry_key(e);
    let want = label_entry_value(e);
    if !label_parts_has(labels, key) { return false; }
    if string.str_compare(label_parts_value(labels, key), want) != 0 { return false; }
    i = i + 1;
  }
  return true;
}

/// True when both sets carry exactly the same key/value entries (order and
/// duplicates aside; both sides are duplicate-free by construction).
pub fn label_parts_equal(a: &LabelParts, b: &LabelParts) -> Bool {
  if label_parts_count(a) != label_parts_count(b) { return false; }
  if !label_parts_matches(a, b) { return false; }
  return label_parts_matches(b, a);
}

// ---------------------------------------------------------------------------
// Owner tables (cluster-wide label stores)
// ---------------------------------------------------------------------------

// Index of `key` among the entries owned by `owner_id`, or -1.
fn _s_owned_find(data: Str, off: &Vec[Int], owner: &Vec[Int], owner_id: Int, key: Str) -> Int {
  let cnt = off.len() - 1;
  if owner.len() != cnt { return -1; }
  var i = 0;
  while i < cnt {
    let o: Int = owner[i];
    if o == owner_id {
      let a: Int = off[i];
      let b: Int = off[i + 1];
      let e: Str = string.str_slice(data, a, b);
      if string.str_compare(label_entry_key(e), key) == 0 { return i; }
    }
    i = i + 1;
  }
  return -1;
}

/// Append one validated entry owned by `owner_id`. `off` and `owner` are
/// mutated and the extended data blob is returned. The owner push happens
/// only on success. Errors: "label: key must not be empty",
/// "label: invalid key", "label: invalid value", "label: duplicate key".
pub fn label_owned_add(data: Str, off: &mut Vec[Int], owner: &mut Vec[Int], owner_id: Int, key: Str, val: Str) -> Result[Str, Str] {
  if string.str_len(key) == 0 { return _s_err_str("label: key must not be empty"); }
  if !label_key_valid(key) { return _s_err_str("label: invalid key"); }
  if !label_value_valid(val) { return _s_err_str("label: invalid value"); }
  if _s_owned_find(data, off, owner, owner_id, key) >= 0 { return _s_err_str("label: duplicate key"); }
  let nd = _s_blob_append(data, off, key + "=" + val);
  owner.push(owner_id);
  return _s_ok_str(nd);
}

/// True when `key` is present among the entries owned by `owner_id`.
pub fn label_owned_has(data: Str, off: &Vec[Int], owner: &Vec[Int], owner_id: Int, key: Str) -> Bool {
  return _s_owned_find(data, off, owner, owner_id, key) >= 0;
}

/// Value of `key` owned by `owner_id`, or "" when absent.
pub fn label_owned_value(data: Str, off: &Vec[Int], owner: &Vec[Int], owner_id: Int, key: Str) -> Str {
  let k = _s_owned_find(data, off, owner, owner_id, key);
  if k < 0 { return ""; }
  return label_entry_value(_s_entry(data, off, k));
}

/// Number of entries owned by `owner_id` (0 on length drift).
pub fn label_owned_count(off: &Vec[Int], owner: &Vec[Int], owner_id: Int) -> Int {
  let cnt = off.len() - 1;
  if owner.len() != cnt { return 0; }
  var k = 0;
  var i = 0;
  while i < cnt {
    let o: Int = owner[i];
    if o == owner_id { k = k + 1; }
    i = i + 1;
  }
  return k;
}

/// Render the entries owned by `owner_id` as "k=v,k2=v2".
pub fn label_owned_render(data: Str, off: &Vec[Int], owner: &Vec[Int], owner_id: Int) -> Str {
  var out = "";
  let cnt = off.len() - 1;
  if owner.len() != cnt { return out; }
  var first = true;
  var i = 0;
  while i < cnt {
    let o: Int = owner[i];
    if o == owner_id {
      if !first { out = out + ","; }
      out = out + _s_entry(data, off, i);
      first = false;
    }
    i = i + 1;
  }
  return out;
}

/// True when every entry owned by `sel_id` in the selector store is present
/// in the object store under `obj_id` (byte-exact keys and values). An empty
/// selector matches everything. Complexity: O(n*m).
pub fn label_owned_matches(data: Str, off: &Vec[Int], owner: &Vec[Int], obj_id: Int,
                           sel_data: Str, sel_off: &Vec[Int], sel_owner: &Vec[Int], sel_id: Int) -> Bool {
  let cnt = sel_off.len() - 1;
  if sel_owner.len() != cnt { return false; }
  var i = 0;
  while i < cnt {
    let o: Int = sel_owner[i];
    if o == sel_id {
      let a: Int = sel_off[i];
      let b: Int = sel_off[i + 1];
      let e: Str = string.str_slice(sel_data, a, b);
      let key = label_entry_key(e);
      let want = label_entry_value(e);
      if !label_owned_has(data, off, owner, obj_id, key) { return false; }
      if string.str_compare(label_owned_value(data, off, owner, obj_id, key), want) != 0 { return false; }
    }
    i = i + 1;
  }
  return true;
}
